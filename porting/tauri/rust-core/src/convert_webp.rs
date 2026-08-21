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

const WEBP_QUALITY: i32 = 75;

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

// ---------------------------------------------------------------------------
// Single file conversion
// ---------------------------------------------------------------------------

/// Process a single CBZ file: convert convertible images to WebP (only if smaller).
/// When `delete_source` is true the original file is deleted after conversion;
/// otherwise it is renamed to `_OLD.cbz` as a backup.
fn process_cbz(file_path: &Path, threads: usize, delete_source: bool) -> Result<(bool, u64, u64), String> {
    // Read the source CBZ into memory.
    let entries = zip_ops::collect_zip_entries_all(file_path)
        .map_err(|e| format!("Cannot read {}: {}", file_path.display(), e))?;

    // Separate ComicInfo.xml from image entries, filter and prepare.
    let mut image_entries: Vec<(String, Vec<u8>)> = Vec::new();
    for entry in &entries {
        if !is_comicinfo_xml(&entry.name) {
            image_entries.push((entry.name.clone(), entry.data.clone()));
        }
    }

    // Collect only convertible entries.
    let mut convertible_indices: Vec<usize> = Vec::new();
    for (i, (name, _)) in image_entries.iter().enumerate() {
        if is_convertible(name) {
            convertible_indices.push(i);
        }
    }

    if convertible_indices.is_empty() {
        return Ok((false, file_path.metadata().map(|m| m.len()).unwrap_or(0), 0));
    }

    // Convert images in parallel (if threads > 1).
    let convert_results: Vec<(usize, bool)> = if threads > 1 {
        convertible_indices.par_iter().map(|&i| -> (usize, bool) {
            let _name = &image_entries[i].0;
            let data = &image_entries[i].1;
            let (_webp_data, was_smaller) = convert_image_to_webp(data, WEBP_QUALITY);
            (i, was_smaller)
        }).collect()
    } else {
        convertible_indices.iter().map(|&i| -> (usize, bool) {
            let _name = &image_entries[i].0;
            let data = &image_entries[i].1;
            let (_webp_data, was_smaller) = convert_image_to_webp(data, WEBP_QUALITY);
            (i, was_smaller)
        }).collect()
    };

    let total_converted: usize = convert_results.iter().filter(|(_, was_smaller)| *was_smaller).count();

    if total_converted == 0 {
        return Ok((false, file_path.metadata().map(|m| m.len()).unwrap_or(0), 0));
    }

    // Build new entry list: renumber pages sequentially.
    let mut new_entries: Vec<zip_ops::ZipEntry> = Vec::new();

    let mut page_num: u32 = 0;
    for (_i, (name, data)) in image_entries.iter().enumerate() {
        if convertible_indices.contains(&&_i) {
            let (_, was_smaller) = convert_results.iter()
                .find(|&&(idx, _)| idx == _i)
                .unwrap();
            if *was_smaller {
                page_num += 1;
                // Use the WebP data (re-convert here — acceptable since it's a small set).
                let (webp_data, _) = convert_image_to_webp(data, WEBP_QUALITY);
                new_entries.push(zip_ops::ZipEntry {
                    name: format!("page_{:04}.webp", page_num),
                    data: webp_data,
                });
            } else {
                // Keep original.
                page_num += 1;
                let ext = get_ext(name);
                new_entries.push(zip_ops::ZipEntry {
                    name: format!("page_{:04}{}", page_num, to_upper_ext(&ext)),
                    data: data.clone(),
                });
            }
        } else {
            // Non-convertible entry — keep original.
            page_num += 1;
            let ext = get_ext(name);
            new_entries.push(zip_ops::ZipEntry {
                name: format!("page_{:04}{}", page_num, to_upper_ext(&ext)),
                data: data.clone(),
            });
        }
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

/// Convert image bytes to WebP. Returns (webp_data, was_smaller).
fn convert_image_to_webp(data: &[u8], quality: i32) -> (Vec<u8>, bool) {
    let original_size = data.len();
    match image_util::convert_bytes_to_webp(data, quality as u32) {
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
/// Supports parallel decoding/encoding via `rayon` (capped at MAX_CONVERT_THREADS = 8).
/// When `delete_source` is true the original file is deleted after conversion;
/// otherwise it is renamed to `_OLD.cbz` as a backup.
pub fn convert_webp(_dir: &Path, files: &[PathBuf], threads: usize, delete_source: bool) -> ConvertResults {
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

            match process_cbz(full_path, threads, delete_source) {
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
pub fn convert_webp_with_progress(
    dir: &Path,
    files: &[PathBuf],
    threads: usize,
    delete_source: bool,
    on_progress: Option<Box<dyn Fn(i32, &str) + Send + Sync>>,
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
        return convert_webp(dir, files, threads, delete_source);
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

            match process_cbz(full_path, threads, delete_source) {
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
