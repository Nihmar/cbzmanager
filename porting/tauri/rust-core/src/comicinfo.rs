/// ComicInfo.xml scan/remove service.
///
/// Replaces `uservicecomicinfo.pas`: `Scan` and `Remove` class methods
/// that operate on a list of CBZ filenames in a directory. Uses rayon for
/// parallel removal (capped at MAX_CBR_CONVERT_THREADS = 4).

use std::path::{Path, PathBuf};
use std::sync::Arc;

use rayon::iter::{IntoParallelIterator, ParallelIterator};

use crate::helpers::*;
use crate::zip_ops;

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

/// Per-file ComicInfo scan/remove result.
#[derive(Debug, Clone)]
#[derive(serde::Serialize, serde::Deserialize)]
pub struct ComicInfoResult {
    pub file_name: String,
    pub has_comicinfo: bool,
    pub removed: bool,
    pub error_msg: String,
}

/// Results for a batch of files.
pub type ComicInfoResults = Vec<ComicInfoResult>;

// ---------------------------------------------------------------------------
// Scan
// ---------------------------------------------------------------------------

/// Determine which CBZ files contain a ComicInfo.xml entry.
pub fn scan(dir: &Path, files: &[&str]) -> ComicInfoResults {
    files
        .iter()
        .map(|&name| {
            let full_path = cbz_full_path(dir, name);
            let mut result = ComicInfoResult {
                file_name: name.to_string(),
                has_comicinfo: false,
                removed: false,
                error_msg: String::new(),
            };

            match zip_ops::collect_zip_entries_all(&full_path) {
                Ok(entries) => {
                    let names: Vec<String> = entries.iter().map(|e| e.name.clone()).collect();
                    result.has_comicinfo = strip_comicinfo_names(&names).len() < names.len();
                }
                Err(e) => {
                    result.error_msg = e.to_string();
                }
            }

            result
        })
        .collect()
}

/// Determine which CBZ files contain a ComicInfo.xml entry, with progress callback.
pub fn scan_with_progress(
    dir: &Path,
    files: &[&str],
    on_progress: Option<Box<dyn Fn(i32, &str) + Send + Sync>>,
) -> ComicInfoResults {
    let progress = on_progress;

    if let Some(ref cb) = progress {
        report_scan_start(cb, "Scanning", files.len());
    }

    if progress.is_none() {
        return scan(dir, files);
    }

    let mut results: ComicInfoResults = Vec::new();

    for (i, &name) in files.iter().enumerate() {
        let full_path = cbz_full_path(dir, name);

        if let Some(ref cb) = progress {
            report_scan_progress(cb, "Scanning", name, i, files.len());
        }

        let mut result = ComicInfoResult {
            file_name: name.to_string(),
            has_comicinfo: false,
            removed: false,
            error_msg: String::new(),
        };

        match zip_ops::collect_zip_entries_all(&full_path) {
            Ok(entries) => {
                let names: Vec<String> = entries.iter().map(|e| e.name.clone()).collect();
                result.has_comicinfo = strip_comicinfo_names(&names).len() < names.len();
            }
            Err(e) => {
                result.error_msg = e.to_string();
            }
        }

        results.push(result);
    }

    if let Some(ref cb) = progress {
        cb(100, "Complete");
    }

    results
}

fn report_scan_start(cb: &Box<dyn Fn(i32, &str) + Send + Sync>, verb: &str, total: usize) {
    if total > 0 {
        cb(0, &format!("{} 0/{} files", verb, total));
    }
}

fn report_scan_progress(cb: &Box<dyn Fn(i32, &str) + Send + Sync>, verb: &str, file_name: &str, index: usize, total: usize) {
    if total > 0 {
        let pct = (index as i32 * 100) / total as i32;
        cb(pct, &format!("{} {} ({}/{})", verb, file_name, index + 1, total));
    }
}

// ---------------------------------------------------------------------------
// Remove (sequential or parallel)
// ---------------------------------------------------------------------------

/// Process a single file: collect entries, remove ComicInfo.xml if present.
fn remove_one(
    file_name: &str,
    full_path: &Path,
    backup: bool,
) -> ComicInfoResult {
    let mut result = ComicInfoResult {
        file_name: file_name.to_string(),
        has_comicinfo: false,
        removed: false,
        error_msg: String::new(),
    };

    match zip_ops::collect_zip_entries_all(full_path) {
        Ok(entries) => {
            let names: Vec<String> = entries.iter().map(|e| e.name.clone()).collect();
            result.has_comicinfo = strip_comicinfo_names(&names).len() < names.len();

            if !result.has_comicinfo {
                return result;
            }

            // Strip ComicInfo.xml and write back.
            let filtered: Vec<zip_ops::ZipEntry> = entries
                .into_iter()
                .filter(|e| !is_comicinfo_xml(&e.name))
                .collect();

            if !filtered.iter().any(|e| zip_ops::is_image_entry(&e.name)) {
                // No image entries survive: writing it back would leave an
                // empty or otherwise invalid CBZ, so keep the original untouched
                // and report the file as skipped rather than corrupting it.
                result.removed = false;
                result.error_msg = "No images to keep".to_string();
                return result;
            }

            if backup {
                if let Err(e) = backup_file(full_path) {
                    result.error_msg = e.to_string();
                    return result;
                }
            }

            match zip_ops::write_zip_from_entries(full_path, &filtered) {
                Ok(()) => {
                    result.removed = true;
                }
                Err(e) => {
                    result.error_msg = e.to_string();
                }
            }
        }
        Err(e) => {
            result.error_msg = e.to_string();
        }
    }

    result
}

/// Strip ComicInfo.xml from CBZ files, optionally creating backups.
pub fn remove(
    dir: &Path,
    files: &[&str],
    backup: bool,
    threads: usize,
) -> ComicInfoResults {
    let progress = None; // CLI mode — no progress callback needed

    let total = files.len();
    report_service_start(progress, "Removing from", total);

    let full_paths: Vec<PathBuf> = files.iter().map(|&f| cbz_full_path(dir, f)).collect();

    let results: Vec<ComicInfoResult> = if threads > 1 {
        // Parallel removal with rayon — iterate by index.
        (0..files.len())
            .into_par_iter()
            .map(|i| {
                let name = files[i];
                let full_path = &full_paths[i];
                report_service_progress(progress, "Removing from", name, i, total);
                remove_one(name, full_path, backup)
            })
            .collect()
    } else {
        // Sequential.
        (0..files.len())
            .map(|i| {
                let name = files[i];
                let full_path = &full_paths[i];
                report_service_progress(progress, "Removing from", name, i, total);
                remove_one(name, full_path, backup)
            })
            .collect()
    };

    if let Some(ref cb) = progress {
        cb(100, "Complete");
    }

    results
}

/// Strip ComicInfo.xml from CBZ files with progress callback.
pub fn remove_with_progress(
    dir: &Path,
    files: &[&str],
    backup: bool,
    threads: usize,
    on_progress: Option<Box<dyn Fn(i32, &str) + Send + Sync>>,
) -> ComicInfoResults {
    if on_progress.is_none() {
        return remove(dir, files, backup, threads);
    }

    let cb = Arc::new(std::sync::Mutex::new(on_progress.unwrap()));
    let total = files.len();

    // Emit start.
    cb.lock().unwrap()(0, &format!("Removing from 0/{} files", total));

    let full_paths: Vec<PathBuf> = files.iter().map(|&f| cbz_full_path(dir, f)).collect();

    let results: Vec<ComicInfoResult> = if threads > 1 {
        (0..files.len())
            .into_par_iter()
            .map({
                let cb = Arc::clone(&cb);
                move |i| {
                    let name = files[i];
                    let full_path = &full_paths[i];

                    let pct = (i as i32 * 100) / total as i32;
                    cb.lock().unwrap()(pct, &format!("Removing from {} ({}/{})", name, i + 1, total));

                    remove_one(name, full_path, backup)
                }
            })
            .collect()
    } else {
        (0..files.len())
            .map(|i| {
                let name = files[i];
                let full_path = &full_paths[i];

                let pct = (i as i32 * 100) / total as i32;
                cb.lock().unwrap()(pct, &format!("Removing from {} ({}/{})", name, i + 1, total));

                remove_one(name, full_path, backup)
            })
            .collect()
    };

    cb.lock().unwrap()(100, "Complete");

    results
}
