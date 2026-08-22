/// Batch CBZ → WebP image conversion service.
///
/// Replaces `userviceconvert.pas`: reads a CBZ entirely in RAM, decodes each
/// image entry, attempts to encode as WebP (quality 75), and keeps the WebP
/// only if it is strictly smaller than the original.  Filters ComicInfo.xml,
/// renames pages sequentially, writes via `zip_ops`.

use std::path::{Path, PathBuf};

use rayon::iter::{IntoParallelIterator, IntoParallelRefIterator, ParallelIterator};

use crate::helpers::*;
use crate::image_util;
use crate::zip_ops;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// Default WebP quality, matching the reference (Pascal/Python default is q75).
const DEFAULT_WEBP_QUALITY: u32 = crate::image_util::WEBP_QUALITY;

// Image extensions recognised as convertible by the app.
const CONVERTIBLE_EXTS: &[&str] = &["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif"];

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

/// Per-file conversion result.
#[derive(Debug, Clone)]
pub struct ConvertResult {
    pub file_name: String,
    pub converted: bool,
    pub original_size: u64,
    pub new_size: u64,
    pub error_msg: String,
}

/// Results for a batch of files.
pub type ConvertResults = Vec<ConvertResult>;

/// Per-file conversion knobs (GAPS 1.6–1.9). `Default` reproduces the reference
/// behaviour: always strip ComicInfo.xml, renumber pages sequentially, convert
/// only when WebP is strictly smaller, and never re-encode an already-WebP page.
#[derive(Debug, Clone, Copy)]
pub struct ConvertOptions {
    /// Filter `ComicInfo.xml` out of the output (default true).
    pub remove_comicinfo: bool,
    /// Renumber surviving pages sequentially (`page_NNNN.ext`). Default true.
    pub renumber_pages: bool,
    /// Only replace a page with its WebP encoding when smaller (default true).
    pub replace_only_if_smaller: bool,
    /// Keep pages already in WebP format without re-encoding them (default true;
    /// mirrors Lazarus `Options.SkipExistingWebP`).
    pub skip_existing_webp: bool,
}

impl Default for ConvertOptions {
    fn default() -> Self {
        Self {
            remove_comicinfo: true,
            renumber_pages: true,
            replace_only_if_smaller: true,
            skip_existing_webp: true,
        }
    }
}

// ---------------------------------------------------------------------------
// Single file conversion
// ---------------------------------------------------------------------------

/// Process a single CBZ file: convert convertible images to WebP (only if smaller).
/// When `delete_source` is true the original file is deleted after conversion;
/// otherwise it is renamed to `_OLD.cbz` as a backup. A `quality` of 0 means
/// "use the default" (q75); any other value is passed straight to the WebP encoder.
fn process_cbz(
    file_path: &Path,
    threads: usize,
    delete_source: bool,
    quality: u32,
    options: ConvertOptions,
) -> Result<(bool, u64, u64), String> {
    let quality = if quality == 0 { DEFAULT_WEBP_QUALITY } else { quality };

    // Per-file worker cap — never exceed Pascal's WebP pool bound.
    let threads = std::cmp::min(threads.max(1), crate::types::MAX_WEBP_THREADS);

    // Read the source CBZ into memory.
    let entries = zip_ops::collect_zip_entries_all(file_path)
        .map_err(|e| format!("Cannot read {}: {}", file_path.display(), e))?;

    // Separate ComicInfo.xml from image entries, filter and prepare.
    let mut image_entries: Vec<(String, Vec<u8>)> = Vec::new();
    for entry in &entries {
        if !options.remove_comicinfo || !is_comicinfo_xml(&entry.name) {
            image_entries.push((entry.name.clone(), entry.data.clone()));
        }
    }

    // Collect only convertible entries.
    let mut convertible_indices: Vec<usize> = Vec::new();
    for (i, (name, _)) in image_entries.iter().enumerate() {
        if is_convertible(name) && !is_webp(name) {
            convertible_indices.push(i);
        }
    }

    // Convert images in parallel (if threads > 1). For each convertible entry we
    // record the payload to keep: None means "keep the original", Some(bytes)
    // means "use this WebP output". Both `skip_existing_webp` and
    // `replace_only_if_smaller` are applied inside `encode_or_keep`.
    let webp_choices: Vec<(usize, Option<Vec<u8>>)> = if threads > 1 {
        convertible_indices.par_iter().map(|&i| encode_or_keep(i, &image_entries[i].0, &image_entries[i].1, quality, options)).collect()
    } else {
        convertible_indices.iter().map(|&i| encode_or_keep(i, &image_entries[i].0, &image_entries[i].1, quality, options))
        .collect()
    };

    // Build the new entry list. Renumbering keeps numbering contiguous across
    // every kept page (converted or not), matching the reference.
    let mut new_entries: Vec<zip_ops::ZipEntry> = Vec::new();
    let mut converted_count: usize = 0;
    let mut page_num: u32 = 0;

    for (i, (name, data)) in image_entries.iter().enumerate() {
        let webp_bytes: Option<Vec<u8>> = webp_choices
            .iter()
            .find(|&&(idx, _)| idx == i)
            .and_then(|(_, b)| b.clone());
        let converted = webp_bytes.is_some();

        page_num += 1; // numbering stays contiguous with renumbering on (off => unused)
        let out_name = if options.renumber_pages {
            let ext = if converted {
                "webp".to_string()
            } else {
                get_ext(name)
            };
            format!("page_{:04}{}", page_num, to_upper_ext(&ext))
        } else {
            name.clone()
        };

        if converted {
            converted_count += 1;
        }
        new_entries.push(zip_ops::ZipEntry {
            name: out_name,
            data: webp_bytes.unwrap_or_else(|| data.clone()),
        });
    }

    // Only rewrite when a page was actually converted (matches the reference: no
    // work => "already up to date", archive left byte-identical).
    if converted_count == 0 {
        return Ok((false, file_path.metadata().map(|m| m.len()).unwrap_or(0), 0));
    }

    // Write the new CBZ.
    let tmp_path = file_path.with_extension("cbz.new");
    zip_ops::write_zip_from_entries(&tmp_path, &new_entries)
        .map_err(|e| format!("Failed to write: {}", e))?;

    let original_size = file_path.metadata().map(|m| m.len()).unwrap_or(0);
    let new_size = tmp_path.metadata().map(|m| m.len()).unwrap_or(0);

    // Replace the original.
    if delete_source {
        // No backup — just atomically swap temp → source.
        std::fs::rename(&tmp_path, file_path)
            .map_err(|e| format!("Failed to replace: {}", e))?;
    } else {
        let old_file = backup_file_path(file_path);
        if old_file.exists() {
            std::fs::remove_file(&old_file).ok();
        }
        std::fs::rename(file_path, &old_file)
            .map_err(|e| format!("Failed to backup: {}", e))?;
        std::fs::rename(&tmp_path, file_path)
            .map_err(|e| format!("Failed to replace: {}", e))?;
    }

    Ok((true, original_size, new_size))
}

/// Check if a filename is convertible (has an image extension).
fn is_convertible(name: &str) -> bool {
    let ext = get_ext(name);
    CONVERTIBLE_EXTS.contains(&ext.to_lowercase().as_str())
}

/// True when the file name is already WebP.
fn is_webp(name: &str) -> bool {
    get_ext(name).to_lowercase() == "webp"
}

/// Decide what bytes to keep for a single convertible entry. Returns `(index, Some(webp_bytes))`
/// when the page is (re-)encoded and `(index, None)` when the original should be kept:
///   * skip_existing_webp — never re-encode an already-WebP page;
///   * replace_only_if_smaller — only keep the WebP output when it is strictly smaller.
fn encode_or_keep(index: usize, name: &str, data: &[u8], quality: u32, options: ConvertOptions) -> (usize, Option<Vec<u8>>) {
    if options.skip_existing_webp && is_webp(name) {
        return (index, None); // keep the existing WebP page as-is
    }
    match convert_image_to_webp(data, quality) {
        (webp_data, true) => (index, Some(webp_data)), // smaller → use WebP
        _ => (index, None),                            // bigger / undecodable → keep original
    }
}

/// Convert image bytes to WebP. Returns (webp_data, was_smaller).
fn convert_image_to_webp(data: &[u8], quality: u32) -> (Vec<u8>, bool) {
    let original_size = data.len();
    match image_util::convert_bytes_to_webp(data, quality) {
        Ok(webp_data) => {
            if webp_data.len() < original_size {
                (webp_data, true)
            } else {
                (data.to_vec(), false)
            }
        }
        Err(_) => (data.to_vec(), false),
    }
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

/// Convert images in CBZ files to WebP format (only if smaller).
///
/// Filters ComicInfo.xml entries, renames pages sequentially.
/// Supports parallel decoding/encoding via `rayon` (capped at MAX_WEBP_THREADS = 8).
/// When `delete_source` is true the original file is deleted after conversion;
/// otherwise it is renamed to `_OLD.cbz` as a backup. `options` carries the
/// GAPS 1.6–1.9 knobs (remove_comicinfo / renumber_pages / replace_only_if_smaller
/// / skip_existing_webp) with defaults matching the reference behaviour.
pub fn convert_webp(
    _dir: &Path,
    files: &[PathBuf],
    threads: usize,
    delete_source: bool,
    quality: u32,
    options: ConvertOptions,
) -> ConvertResults {
    let progress = None;

    let total = files.len();
    report_service_start(progress, "Converting", total);

    let results: Vec<ConvertResult> = (0..files.len())
        .into_par_iter()
        .map(|i| {
            let name = files[i].file_name().unwrap_or_default().to_string_lossy().to_string();
            let full_path = &files[i];
            report_service_progress(progress, "Converting", &name, i, total);

            let mut result = ConvertResult {
                file_name: name.clone(),
                converted: false,
                original_size: 0,
                new_size: 0,
                error_msg: String::new(),
            };

            match process_cbz(full_path, threads, delete_source, quality, options) {
                Ok((changed, orig, new)) => {
                    result.converted = changed;
                    result.original_size = orig;
                    result.new_size = new;
                }
                Err(e) => {
                    result.error_msg = e;
                }
            }

            result
        })
        .collect();

    results
}

/// Convert images in CBZ files to WebP format with progress reporting.
///
/// Accepts an optional boxed callback that can be cloned into rayon workers.
/// When `delete_source` is true the original file is deleted after conversion.
/// `options` carries the GAPS 1.6–1.9 knobs (defaults match the reference).
pub fn convert_webp_with_progress(
    dir: &Path,
    files: &[PathBuf],
    threads: usize,
    delete_source: bool,
    quality: u32,
    on_progress: Option<Box<dyn Fn(i32, &str) + Send + Sync>>,
    options: ConvertOptions,
) -> ConvertResults {
    let progress = on_progress;

    let total = files.len();
    if let Some(ref cb) = progress {
        if total > 0 {
            cb(0, &format!("Converting 0/{} files", total));
        }
    }

    // If no callback provided, use the standard non-progress path
    if progress.is_none() {
        return convert_webp(dir, files, threads, delete_source, quality, options);
    }

    let results: Vec<ConvertResult> = (0..files.len())
        .into_par_iter()
        .map(|i| {
            let name = files[i].file_name().unwrap_or_default().to_string_lossy().to_string();
            let full_path = &files[i];

            if let Some(ref cb) = progress {
                if total > 0 {
                    let pct = (i as i32 * 100) / total as i32;
                    cb(pct, &format!("Converting {} ({}/{})", name, i + 1, total));
                }
            }

            let mut result = ConvertResult {
                file_name: name.clone(),
                converted: false,
                original_size: 0,
                new_size: 0,
                error_msg: String::new(),
            };

            match process_cbz(full_path, threads, delete_source, quality, options) {
                Ok((changed, orig, new)) => {
                    result.converted = changed;
                    result.original_size = orig;
                    result.new_size = new;
                }
                Err(e) => {
                    result.error_msg = e;
                }
            }

            result
        })
        .collect();

    if let Some(ref cb) = progress {
        cb(100, "Complete");
    }

    results
}
