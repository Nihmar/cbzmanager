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
        return Ok((false, cbr_path.metadata().map(|m| m.len()).unwrap_or(0), 0));
    }

    // Sort entries alphabetically and renumber sequentially.
    let mut sorted_entries: Vec<zip_ops::ZipEntry> = new_entries;
    sorted_entries.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));

    let padding = page_padding_for(sorted_entries.len());

    let mut renamed_entries: Vec<zip_ops::ZipEntry> = Vec::new();
    for (i, entry) in sorted_entries.iter().enumerate() {
        let ext = get_ext(&entry.name);
        let new_name = format!("page_{:0>width$}{}", i + 1, to_upper_ext(&ext), width = padding as usize);
        renamed_entries.push(zip_ops::ZipEntry {
            name: new_name,
            data: entry.data.clone(),
        });
    }

    // Write the CBZ entirely in RAM.
    let tmp_path = cbr_path.with_extension("cbz.new");
    zip_ops::write_zip_from_entries(&tmp_path, &renamed_entries)
        .map_err(|e| format!("Failed to write CBZ: {}", e))?;

    let original_size = cbr_path.metadata().map(|m| m.len()).unwrap_or(0);
    let new_size = tmp_path.metadata().map(|m| m.len()).unwrap_or(0);

    // Replace the CBR source.
    if delete_source {
        std::fs::remove_file(cbr_path)
            .map_err(|e| format!("Failed to delete source: {}", e))?;
        std::fs::rename(&tmp_path, cbr_path)
            .map_err(|e| format!("Failed to replace: {}", e))?;
    } else {
        let old_file = backup_file_path(cbr_path);
        if old_file.exists() {
            std::fs::remove_file(&old_file).ok();
        }
        std::fs::rename(cbr_path, &old_file)
            .map_err(|e| format!("Failed to backup: {}", e))?;
        std::fs::rename(&tmp_path, cbr_path)
            .map_err(|e| format!("Failed to replace: {}", e))?;
    }

    Ok((true, original_size, new_size))
}

/// Get extension from filename.
fn get_ext(name: &str) -> String {
    name.rsplit_once('.').map(|(_, e)| e.to_string()).unwrap_or_else(|| "jpg".to_string())
}

/// Return a lower-case extension for use in renumbered names.
fn to_upper_ext(ext: &str) -> String {
    format!(".{}", ext.to_lowercase())
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
/// Filters ComicInfo.xml entries, renames pages sequentially.
/// Supports skip-existing (by checking for target .cbz) and delete-source.
/// Parallel per-file conversion pool, capped at MAX_CBR_CONVERT_THREADS = 4.
pub fn convert_cbr_to_cbz(
    _dir: &Path,
    files: &[PathBuf],
    threads: usize,
    _skip_existing: bool,
) -> CbrConvertResults {
    let progress = None; // CLI mode — no progress callback needed

    report_service_start(progress, "Converting CBR", files.len());

    let results: Vec<Result<CbrConvertResult, String>> = if threads > 1 {
        files.par_iter().enumerate()
            .map(|(i, full_path)| {
                let name = full_path.file_name().unwrap_or_default().to_string_lossy().to_string();
                report_service_progress(progress, "Converting CBR", &name, i, files.len());
                process_cbr(full_path, false).map(|(changed, orig, new)| CbrConvertResult {
                    file_name: name.clone(),
                    converted: changed,
                    original_size: orig,
                    new_size: new,
                    error_msg: String::new(),
                })
            }).collect::<Vec<_>>()
    } else {
        files.iter().enumerate()
            .map(|(i, full_path)| {
                let name = full_path.file_name().unwrap_or_default().to_string_lossy().to_string();
                report_service_progress(progress, "Converting CBR", &name, i, files.len());
                process_cbr(full_path, false).map(|(changed, orig, new)| CbrConvertResult {
                    file_name: name.clone(),
                    converted: changed,
                    original_size: orig,
                    new_size: new,
                    error_msg: String::new(),
                })
            }).collect::<Vec<_>>()
    };

    if let Some(ref cb) = progress {
        cb(100, "Complete");
    }

    results.into_iter().map(|r| match r {
        Ok(result) => result,
        Err(e) => CbrConvertResult {
            file_name: String::new(),
            converted: false,
            original_size: 0,
            new_size: 0,
            error_msg: e,
        },
    }).collect()
}

/// Convert CBR archives to CBZ format with progress callback.
pub fn convert_cbr_to_cbz_with_progress(
    _dir: &Path,
    files: &[PathBuf],
    threads: usize,
    _skip_existing: bool,
    on_progress: Option<Box<dyn Fn(i32, &str) + Send + Sync>>,
) -> CbrConvertResults {
    if on_progress.is_none() {
        return convert_cbr_to_cbz(_dir, files, threads, _skip_existing);
    }

    let cb = Arc::new(std::sync::Mutex::new(on_progress.unwrap()));
    let total = files.len();

    // Emit start.
    cb.lock().unwrap()(0, &format!("Converting CBR 0/{} files", total));

    let results: Vec<Result<CbrConvertResult, String>> = if threads > 1 {
        files.par_iter().enumerate()
            .map({
                let cb = Arc::clone(&cb);
                move |(i, full_path)| {
                    let name = full_path.file_name().unwrap_or_default().to_string_lossy().to_string();

                    let pct = (i as i32 * 100) / total as i32;
                    cb.lock().unwrap()(pct, &format!("Converting CBR {} ({}/{})", name, i + 1, total));

                    process_cbr(full_path, false).map(|(changed, orig, new)| CbrConvertResult {
                        file_name: name.clone(),
                        converted: changed,
                        original_size: orig,
                        new_size: new,
                        error_msg: String::new(),
                    })
                }
            }).collect::<Vec<_>>()
    } else {
        files.iter().enumerate()
            .map(|(i, full_path)| {
                let name = full_path.file_name().unwrap_or_default().to_string_lossy().to_string();

                let pct = (i as i32 * 100) / total as i32;
                cb.lock().unwrap()(pct, &format!("Converting CBR {} ({}/{})", name, i + 1, total));

                process_cbr(full_path, false).map(|(changed, orig, new)| CbrConvertResult {
                    file_name: name.clone(),
                    converted: changed,
                    original_size: orig,
                    new_size: new,
                    error_msg: String::new(),
                })
            }).collect::<Vec<_>>()
    };

    cb.lock().unwrap()(100, "Complete");

    results.into_iter().map(|r| match r {
        Ok(result) => result,
        Err(e) => CbrConvertResult {
            file_name: String::new(),
            converted: false,
            original_size: 0,
            new_size: 0,
            error_msg: e,
        },
    }).collect()
}
