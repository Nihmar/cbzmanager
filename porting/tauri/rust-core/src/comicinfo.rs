/// ComicInfo.xml scan/remove service.
///
/// Replaces `uservicecomicinfo.pas`: `Scan` and `Remove` class methods
/// that operate on a list of CBZ filenames in a directory. Uses rayon for
/// parallel removal (capped at MAX_CBR_CONVERT_THREADS = 4).

use std::path::{Path, PathBuf};

use rayon::iter::{IntoParallelIterator, ParallelIterator};

use crate::helpers::*;
use crate::zip_ops;

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

/// Per-file ComicInfo scan/remove result.
#[derive(Debug, Clone)]
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
