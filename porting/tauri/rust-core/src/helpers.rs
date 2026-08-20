/// Shared helper functions for CBZ Manager services.
///
/// Replaces `uservicebase.pas` utility routines: backup, replace, file
/// collection, CPU count, and progress-reporting helpers.

use std::fs;
use std::path::{Path, PathBuf};

use rayon::current_num_threads;

use crate::types::*;

/// ---------------------------------------------------------------------------
/// File I/O helpers
/// ---------------------------------------------------------------------------

/// Build the backup suffix path: strip extension, add BACKUP_SUFFIX.
pub fn backup_file_path(file_path: &Path) -> PathBuf {
    let stem = file_path
        .file_stem()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_default();
    file_path.with_file_name(format!("{}{}", stem, BACKUP_SUFFIX))
}

/// Rename a file to a _OLD.cbz backup.
///
/// Constructs the backup name by replacing the extension with "_OLD.cbz"
/// (e.g. "manga.cbz" → "manga_OLD.cbz"). If a previous _OLD.cbz already
/// exists it is silently deleted before the rename.
pub fn backup_file(file_path: &Path) -> std::io::Result<()> {
    let old_file = backup_file_path(file_path);
    if old_file.exists() {
        fs::remove_file(&old_file)?;
    }
    fs::rename(file_path, &old_file)?;
    Ok(())
}

/// Atomically replace a CBZ file with new in-memory entries.
///
/// Four-step algorithm:
///   1. Write entries to a ".new" temp file.
///   2. Delete any existing _OLD backup.
///   3. Rename original → _OLD.
///   4. Rename .new → original.
/// If any step fails, roll back as much as possible.
pub fn replace_cbz<F>(file_path: &Path, write_entries: F) -> std::io::Result<()>
where
    F: FnOnce(&Path) -> std::io::Result<()>,
{
    let old_file = backup_file_path(file_path);
    let new_file = file_path.with_extension("cbz.new");

    // Step 1: write new entries to temp file.
    if let Err(e) = write_entries(&new_file) {
        let _ = fs::remove_file(&new_file);
        return Err(e);
    }

    // Step 2: remove stale backup.
    if old_file.exists() {
        fs::remove_file(&old_file)?;
    }

    // Step 3: rename original → backup.
    if let Err(e) = fs::rename(file_path, &old_file) {
        fs::remove_file(&new_file)?;
        return Err(e);
    }

    // Step 4: rename .new → original.
    if let Err(e) = fs::rename(&new_file, file_path) {
        // Rollback: restore from backup.
        let _ = fs::rename(&old_file, file_path);
        let _ = fs::remove_file(&new_file);
        return Err(e);
    }

    Ok(())
}

/// ---------------------------------------------------------------------------
/// File collection (case-insensitive extension matching)
/// ---------------------------------------------------------------------------

/// Collect *.cbz (and *.CBZ) filenames from a directory (non-recursive).
pub fn collect_cbz_files(dir: &Path) -> Vec<PathBuf> {
    collect_files_by_ext(dir, CBZ_EXT)
}

/// Collect *.cbr (and *.CBR) filenames from a directory (non-recursive).
pub fn collect_cbr_files(dir: &Path) -> Vec<PathBuf> {
    collect_files_by_ext(dir, CBR_EXT)
}

fn collect_files_by_ext(dir: &Path, target_ext: &str) -> Vec<PathBuf> {
    let mut result = Vec::new();
    let dir = dir.to_path_buf();
    if let Ok(entries) = fs::read_dir(&dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_file() {
                if let Some(ext) = path.extension() {
                    if ext.eq_ignore_ascii_case(target_ext.trim_start_matches('.')) {
                        result.push(path);
                    }
                }
            }
        }
    }
    // Sort for deterministic ordering (matches Pascal's FindFirst/FindNext +
    // case-insensitive extension matching).
    result.sort();
    result
}

/// ---------------------------------------------------------------------------
/// Path utilities
/// ---------------------------------------------------------------------------

/// Join a directory and a bare filename into a full path.
pub fn cbz_full_path(dir: &Path, file_name: &str) -> PathBuf {
    dir.join(file_name)
}

/// Extract the zero-based page index from a renumbered page name (page_NNNN.ext).
/// Returns None if the name doesn't match the pattern.
pub fn page_index_from_name(name: &str) -> Option<usize> {
    let stem = name.rsplit_once('.').map(|(s, _)| s).unwrap_or(name);
    if !stem.starts_with("page_") {
        return None;
    }
    stem["page_".len()..].parse::<usize>().ok()
}

/// ---------------------------------------------------------------------------
/// CPU count
/// ---------------------------------------------------------------------------

/// Number of online CPUs for automatic worker-pool sizes.
///
/// Uses rayon's current_num_threads which reports the available OS threads.
/// Always returns >= 1.
pub fn online_cpu_count() -> usize {
    let count = current_num_threads();
    std::cmp::max(count, 1)
}

/// ---------------------------------------------------------------------------
/// Progress helpers
/// ---------------------------------------------------------------------------

/// Fold a within-file percentage into a global one across a batch of files.
///
/// (file_index * 100 + within_file) / file_total gives 0-100 across the whole
/// batch: file 0 of 4 at 50% → 12, file 3 of 4 at 100% → 100.
pub fn global_file_percent(file_index: i32, file_total: i32, within_file: i32) -> i32 {
    if file_total <= 0 {
        return 0;
    }
    (file_index * 100 + within_file) / file_total
}

/// Emit the initial progress message for a service operation.
pub fn report_service_start(
    on_progress: Option<&ServiceProgressFn>,
    verb: &str,
    total: usize,
) {
    if let Some(cb) = on_progress {
        if total > 0 {
            cb(0, &format!("{} 0/{} files", verb, total));
        }
    }
}

/// Emit a per-file progress message.
pub fn report_service_progress(
    on_progress: Option<&ServiceProgressFn>,
    verb: &str,
    file_name: &str,
    index: usize,
    total: usize,
) {
    if let Some(cb) = on_progress {
        if total > 0 {
            let pct = (index as i32 * 100) / total as i32;
            cb(pct, &format!("{} {} ({}/{})", verb, file_name, index + 1, total));
        }
    }
}

/// ---------------------------------------------------------------------------
/// Page name formatting
/// ---------------------------------------------------------------------------

/// Format a page name with zero-padded number: "page_0001.jpg".
pub fn format_page_name(page_num: usize, padding: usize, ext: &str) -> String {
    let padded = format!("{:0>width$}", page_num, width = padding);
    format!("page_{}{}", padded, ext)
}

/// Compute zero-padding width for an archive of `page_count` pages.
/// Uses PAGE_PAD_MIN, widened when the count needs more digits.
pub fn page_padding_for(page_count: usize) -> usize {
    let mut result = PAGE_PAD_MIN;
    let digits = (page_count as f64).log10().floor() as usize + 1;
    if page_count > 0 && digits > result {
        result = digits;
    }
    // Special case: 0 pages → use default.
    if page_count == 0 {
        result = PAGE_PAD_DEFAULT;
    }
    result
}

/// ---------------------------------------------------------------------------
/// ComicInfo.xml helpers
/// ---------------------------------------------------------------------------

/// Check whether a file name matches ComicInfo.xml (case-insensitive).
pub fn is_comicinfo_xml(name: &str) -> bool {
    name.eq_ignore_ascii_case(COMICINFO_XML)
}

/// Filter out ComicInfo.xml entries from a list of entry names, returning
/// only the surviving names.
pub fn strip_comicinfo_names(names: &[String]) -> Vec<String> {
    names
        .iter()
        .filter(|n| !is_comicinfo_xml(n))
        .cloned()
        .collect()
}

/// Find the index of the ComicInfo.xml entry in a list of names, or None.
pub fn find_comicinfo_index(names: &[String]) -> Option<usize> {
    names.iter().position(|n| is_comicinfo_xml(n))
}
