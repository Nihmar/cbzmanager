/// Batch CBR → CBZ conversion service.
///
/// Replaces `uservicecbr.pas`: reads CBR archives via libarchive, filters
/// ComicInfo.xml, renames pages sequentially, writes as CBZ (DEFLATE).
/// Files are converted in parallel via a worker pool (capped at MAX_CBR_CONVERT_THREADS = 4).
/// Supports skip-existing and delete-source options.

use std::path::{Path, PathBuf};
use std::sync::Arc;

use rayon::iter::{IndexedParallelIterator, IntoParallelRefIterator, ParallelIterator};

use crate::helpers::*;
use crate::types::MAX_CBR_THREADS;
use crate::zip_ops;
use crate::cbr_reader;

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

/// Per-file CBR→CBZ conversion result.
#[derive(Debug, Clone)]
pub struct CbrConvertResult {
    pub file_name: String,
    pub converted: bool,
    pub original_size: u64,
    pub new_size: u64,
    pub error_msg: String,
}

/// Results for a batch of files.
pub type CbrConvertResults = Vec<CbrConvertResult>;

// ---------------------------------------------------------------------------
// Single file conversion
// ---------------------------------------------------------------------------

/// Process a single CBR file: extract images, filter ComicInfo.xml, write as CBZ.
fn process_cbr(
    cbr_path: &Path,
    delete_source: bool,
) -> Result<(bool, u64, u64), String> {
    let mut new_entries: Vec<zip_ops::ZipEntry> = Vec::new();

    // Try CBR reader first (for actual RAR archives).
    if cbr_reader::cbr_supported() {
        match cbr_reader::collect_cbr_entries(cbr_path) {
            Ok(cbr_entries) => {
                for (name, data) in cbr_entries {
                    if !is_comicinfo_xml(&name) {
                        new_entries.push(zip_ops::ZipEntry { name, data });
                    }
                }
            }
            Err(e) => {
                // Not a RAR archive or read error — try treating as ZIP.
                eprintln!("CBR reader failed for {}: {} — trying ZIP fallback", cbr_path.display(), e);
            }
        }
    }

    // If CBR reader didn't yield entries, try treating file as ZIP.
    if new_entries.is_empty() {
        let zip_entries = match zip_ops::collect_zip_entries_all(cbr_path) {
            Ok(entries) => entries,
            Err(e) => return Err(format!("Cannot read {}: {}", cbr_path.display(), e)),
        };
        for entry in zip_entries {
            if !is_comicinfo_xml(&entry.name) {
                new_entries.push(zip_ops::ZipEntry {
                    name: entry.name.clone(),
                    data: entry.data,
                });
            }
        }
    }

    if new_entries.is_empty() {
        // Nothing converted — leave no target behind so skip-existing stays meaningful.
        return Ok((false, cbr_path.metadata().map(|m| m.len()).unwrap_or(0), 0));
    }

    // Sort entries alphabetically and renumber sequentially.
    let mut sorted_entries: Vec<zip_ops::ZipEntry> = new_entries;
    sorted_entries.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));

    let padding = page_padding_for(sorted_entries.len());

    let mut renamed_entries: Vec<zip_ops::ZipEntry> = Vec::new();
    for (i, entry) in sorted_entries.iter().enumerate() {
        let ext = get_ext(&entry.name);
        let new_name = format!("page_{:0>width$}{}", i + 1, with_ext(&ext), width = padding as usize);
        renamed_entries.push(zip_ops::ZipEntry {
            name: new_name,
            data: entry.data.clone(),
        });
    }

    // Write the CBZ output entirely in RAM first (into a temp file beside the target).
    let target = target_for(cbr_path);
    let tmp_path = std::path::PathBuf::from(format!("{}.tmp", target.display()));
    zip_ops::write_zip_from_entries(&tmp_path, &renamed_entries)
        .map_err(|e| format!("Failed to write {}: {}", target.display(), e))?;

    // Atomically move the freshly-written CBZ into place.
    std::fs::rename(&tmp_path, &target)
        .map_err(|e| format!("Failed to write {}: {}", target.display(), e))?;

    let original_size = cbr_path.metadata().map(|m| m.len()).unwrap_or(0);
    let new_size = target.metadata().map(|m| m.len()).unwrap_or(0);

    // Delete the .cbr source only after the .cbz has been written successfully.
    if delete_source {
        std::fs::remove_file(cbr_path)
            .map_err(|e| format!("Converted, but failed to delete {}: {}", cbr_path.display(), e))?;
    }

    Ok((true, original_size, new_size))
}

/// The `.cbz` file that a `.cbr` source converts into (mirrors Pascal's
/// `ChangeFileExt(FullPath, CBZ_EXT)`).
fn target_for(cbr_path: &Path) -> std::path::PathBuf {
    cbr_path.with_extension("cbz")
}

/// Get extension from filename.
fn get_ext(name: &str) -> String {
    name.rsplit_once('.').map(|(_, e)| e.to_string()).unwrap_or_else(|| "jpg".to_string())
}

/// Prefix a file name with its original (unchanged) extension, for renumbered
/// page names. The case is preserved — decoding is magic-byte based, so the
/// renamed extension is cosmetic; matching the Python reference keeps the
/// source casing instead of forcing lower/upper case.
fn with_ext(ext: &str) -> String {
    format!(".{}", ext)
}

// ---------------------------------------------------------------------------
// Batch conversion
// ---------------------------------------------------------------------------

/// Collect CBR files from a directory (case-insensitive .cbr).
pub fn collect_cbr_files(dir: &Path) -> Vec<String> {
    let mut files: Vec<String> = Vec::new();
    if let Ok(entries) = std::fs::read_dir(dir) {
        for entry in entries.flatten() {
            if let (Some(filename), Some(ext)) = (
                entry.file_name().to_str().map(|s| s.to_string()),
                entry.path().extension().and_then(|e| e.to_str()),
            ) {
                if ext.eq_ignore_ascii_case("cbr") {
                    files.push(filename);
                }
            }
        }
    }
    files.sort_by(|a, b| a.to_lowercase().cmp(&b.to_lowercase()));
    files
}

/// Convert CBR archives to CBZ format.
///
/// Filters ComicInfo.xml entries, renames pages sequentially, writes as a `.cbz`
/// next to the source. Honours skip-existing (never overwrites an existing target)
/// and delete-source (the `.cbr` is removed only after the `.cbz` is written).
/// Files are converted in parallel via a rayon worker pool capped at `MAX_CBR_THREADS`.
pub fn convert_cbr_to_cbz(
    _dir: &Path,
    files: &[PathBuf],
    threads: usize,
    delete_source: bool,
    skip_existing: bool,
) -> CbrConvertResults {
    // GAPS 1.3: cap the worker count at MAX_CBR_THREADS (was previously unbounded).
    let threads = std::cmp::max(1, std::cmp::min(threads, MAX_CBR_THREADS));

    report_service_start(None, "Converting CBR", files.len());

    let results: Vec<CbrConvertResult> = if threads > 1 {
        files
            .par_iter()
            .map(|full_path| convert_one(full_path, delete_source, skip_existing))
            .collect()
    } else {
        files
            .iter()
            .map(|full_path| convert_one(full_path, delete_source, skip_existing))
            .collect()
    };

    results
}

/// Convert (or skip) a single CBR file.
fn convert_one(
    full_path: &Path,
    delete_source: bool,
    skip_existing: bool,
) -> CbrConvertResult {
    let name = full_path.file_name().unwrap_or_default().to_string_lossy().to_string();

    // GAPS 1.2: never overwrite an existing target `.cbz`.
    if skip_existing && target_for(full_path).exists() {
        let original_size = std::fs::metadata(full_path).map(|m| m.len()).unwrap_or(0);
        return CbrConvertResult {
            file_name: name,
            converted: false,
            original_size,
            new_size: 0,
            error_msg: format!(
                "Target {} already exists — skipped",
                target_for(full_path).display()
            ),
        };
    }

    match process_cbr(full_path, delete_source) {
        Ok((changed, original_size, new_size)) => CbrConvertResult {
            file_name: name,
            converted: changed,
            original_size,
            new_size,
            error_msg: String::new(),
        },
        Err(e) => CbrConvertResult {
            file_name: name,
            converted: false,
            original_size: 0,
            new_size: 0,
            error_msg: e,
        },
    }
}

/// Convert CBR archives to CBZ format with progress callback.
pub fn convert_cbr_to_cbz_with_progress(
    _dir: &Path,
    files: &[PathBuf],
    threads: usize,
    delete_source: bool,
    skip_existing: bool,
    on_progress: Option<Box<dyn Fn(i32, &str) + Send + Sync>>,
) -> CbrConvertResults {
    if on_progress.is_none() {
        return convert_cbr_to_cbz(_dir, files, threads, delete_source, skip_existing);
    }

    let cb = Arc::new(std::sync::Mutex::new(on_progress.unwrap()));
    let total = files.len();

    // GAPS 1.3: cap the worker count at MAX_CBR_THREADS.
    let threads = std::cmp::max(1, std::cmp::min(threads, MAX_CBR_THREADS));

    cb.lock().unwrap()(0, &format!("Converting CBR 0/{} files", total));

    let results: Vec<CbrConvertResult> = if threads > 1 {
        let cb2 = Arc::clone(&cb);
        files
            .par_iter()
            .enumerate()
            .map(|(i, full_path)| {
                let pct = (i as i32 * 100) / total as i32;
                let name = full_path
                    .file_name()
                    .unwrap_or_default()
                    .to_string_lossy()
                    .to_string();
                cb2.lock().unwrap()(pct, &format!("Converting CBR {} ({}/{})", name, i + 1, total));
                convert_one(full_path, delete_source, skip_existing)
            })
            .collect()
    } else {
        files
            .iter()
            .enumerate()
            .map(|(i, full_path)| {
                let pct = (i as i32 * 100) / total as i32;
                let name = full_path
                    .file_name()
                    .unwrap_or_default()
                    .to_string_lossy()
                    .to_string();
                cb.lock().unwrap()(pct, &format!("Converting CBR {} ({}/{})", name, i + 1, total));
                convert_one(full_path, delete_source, skip_existing)
            })
            .collect()
    };

    cb.lock().unwrap()(100, "Complete");
    results
}
