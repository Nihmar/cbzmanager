/// Merge chapter CBZ files into volumes based on existing volume average.
///
/// Replaces `uservicemerge.pas`: parses CBZ filenames into chapters and volumes,
/// groups by series, calculates CPV (chapters-per-volume), batches chapters into
/// volume CBZ files, writes them entirely in RAM with sequential page naming.

use std::cmp;
use std::path::{Path, PathBuf};

use crate::helpers::*;

use crate::zip_ops;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// Parsed chapter file: (series_name, chapter_number, path).
#[derive(Debug, Clone)]
pub struct ChapterFile {
    pub series: String,
    pub chapter_num: i32,
    pub path: PathBuf,
}

/// Parsed volume file: (series_name, volume_tag, path).
#[derive(Debug, Clone)]
pub struct VolumeFile {
    pub series: String,
    pub volume_tag: String,
    pub path: PathBuf,
}

/// Output specification for one merged volume.
#[derive(Debug, Clone)]
pub struct VolumeSpec {
    pub output_path: PathBuf,
    pub chapter_paths: Vec<PathBuf>,
    pub num_pages: usize,
}

/// Plan for one series merge.
#[derive(Debug, Default)]
pub struct SeriesPlan {
    pub series_name: String,
    pub ch_list: Vec<ChapterFile>,
    pub volumes: Vec<VolumeSpec>,
    pub ch_index: usize,
    pub remaining: usize,
}

/// A single output volume produced by a merge operation.
#[derive(Debug, Clone)]
pub struct MergeVolumeResult {
    /// Title of the resulting volume (e.g. "Series Name V01").
    pub title: String,
    /// Output file path for the merged CBZ.
    pub output_path: PathBuf,
    /// Source chapter files included in this volume.
    pub chapters: Vec<PathBuf>,
}

/// Merge result for one series.
#[derive(Debug, Clone)]
pub struct SeriesMergeResult {
    pub series_name: String,
    pub volumes_created: usize,
    pub total_pages: usize,
    /// Actual volume output metadata (paths, chapter list).
    pub volumes: Vec<MergeVolumeResult>,
    pub error_msg: String,
}

/// Results for a merge batch.
pub type MergeResults = Vec<SeriesMergeResult>;

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

/// Pattern for chapter files: `Series - NNNN.cbz` or `Series - SP01.cbz`.
const CHAPTER_RE: &str = r"^(.+)\s-\s(\d+)(?:_\d+)*(?i:\.cbz)$";
const SPECIAL_RE: &str = r"^(.+)\s- ([A-Za-z][A-Za-z0-9]*)(?:_\d+)*(?i:\.cbz)$";
const VOLUME_RE: &str = r"^(.+)\s(V\d+)(?i:\.cbz)$";

/// Parse CBZ files in a directory into chapters and volumes.
 pub fn parse_cbz_files(dir: &Path) -> (Vec<ChapterFile>, Vec<VolumeFile>) {
     let mut chapters: Vec<(String, i32, PathBuf)> = Vec::new();
     let mut volumes: Vec<(String, String, PathBuf)> = Vec::new();
     let mut specials: Vec<(String, String, PathBuf)> = Vec::new();

     // Collect .cbz files (case-insensitive).
     if let Ok(entries) = dir.read_dir() {
         for entry in entries.flatten() {
             if let Some(ext) = entry.path().extension().and_then(|s| s.to_str()) {
                 if !ext.eq_ignore_ascii_case("cbz") {
                     continue;
                 }
             } else {
                 continue;
             }

              let path = entry.path();
              let name = path.file_name()
                  .and_then(|s| s.to_str())
                  .unwrap_or("");

             // Try chapter pattern.
             if let Some(caps) = extract_captures(CHAPTER_RE, &name) {
                 if caps.len() >= 3 {
                     if let Ok(num) = caps[2].parse::<i32>() {
                         chapters.push((caps[1].to_string(), num, path));
                         continue;
                     }
                 }
             }

             // Try special chapter pattern.
             if let Some(caps) = extract_captures(SPECIAL_RE, &name) {
                 if caps.len() >= 3 {
                     specials.push((caps[1].to_string(), caps[2].to_string(), path));
                     continue;
                 }
             }

             // Try volume pattern.
             if let Some(caps) = extract_captures(VOLUME_RE, &name) {
                 if caps.len() >= 3 {
                     volumes.push((caps[1].to_string(), caps[2].to_string(), path));
                     continue;
                 }
             }
         }
     }

     // Assign sequential numbers to special chapters.
     let mut max_by_series: std::collections::HashMap<String, i32> = std::collections::HashMap::new();
     for (s, n, _) in &chapters {
         let entry = max_by_series.entry(s.clone()).or_insert(0);
         *entry = (*entry).max(*n);
     }

     let mut special_map: std::collections::HashMap<String, Vec<(String, PathBuf)>> = std::collections::HashMap::new();
     for (series, tag, path) in specials {
         special_map.entry(series).or_default().push((tag, path));
     }

    for (series, mut sp_list) in special_map {
        let next_num = max_by_series.get(&series).copied().unwrap_or(0) + 1;
        sp_list.sort_by(|a, b| a.0.cmp(&b.0));
        for (_j, (_tag, path)) in sp_list.iter().enumerate() {
            let ch_num = next_num + _j as i32;
            chapters.push((series.clone(), ch_num, path.clone()));
        }
    }

     // Sort chapters by series then number.
     chapters.sort_by(|a, b| a.0.cmp(&b.0).then(a.1.cmp(&b.1)));
     volumes.sort_by(|a, b| a.0.cmp(&b.0).then(a.1.cmp(&b.1)));

     let chapters: Vec<ChapterFile> = chapters.into_iter().map(|(s, n, p)| ChapterFile { series: s, chapter_num: n, path: p }).collect();
     let volumes: Vec<VolumeFile> = volumes.into_iter().map(|(s, v, p)| VolumeFile { series: s, volume_tag: v, path: p }).collect();

     (chapters, volumes)
 }

/// Helper: extract regex captures. Simple pattern matching since we don't have regex crate.
fn extract_captures(pattern: &str, name: &str) -> Option<Vec<String>> {
    use regex::Regex;

    // Match filename patterns like "Series - NNNN" or "Series - NNNN Chapter".
    if let Ok(re) = Regex::new(pattern) {
        if let Some(caps) = re.captures(name) {
            let captures: Vec<String> = caps.iter()
                .filter_map(|m| m.map(|s| s.as_str().to_string()))
                .collect();
            return Some(captures);
        }
    }
    None
}

// ---------------------------------------------------------------------------
// Merge a single volume
// ---------------------------------------------------------------------------

/// Merge multiple CBZ files into a single flat CBZ with sequential image names.
/// Filters ComicInfo.xml, renames pages sequentially. When `generate_comicinfo`
/// is true a generated `ComicInfo.xml` is embedded in the volume (mirrors
/// Lazarus `Options.GenerateComicInfo`).
/// Returns (number_of_images_written, error).
fn merge_cbz_files(
    source_paths: &[PathBuf],
    output_path: &Path,
    generate_comicinfo: bool,
) -> Result<usize, String> {
    // Count total images first (for padding).
    let mut total_images = 0usize;
    for cbz_path in source_paths {
        if let Ok(entries) = zip_ops::collect_zip_entries_all(cbz_path) {
            for entry in &entries {
                if !is_comicinfo_xml(&entry.name) {
                    total_images += 1;
                }
            }
        }
    }

    let padding = cmp::max(3, format!("{}", total_images).len());
    let mut page_num = 0u32;
    let mut new_entries: Vec<zip_ops::ZipEntry> = Vec::new();

    for cbz_path in source_paths {
        match zip_ops::collect_zip_entries_all(cbz_path) {
            Ok(entries) => {
                // Sort entries alphabetically.
                let mut sorted_entries: Vec<&zip_ops::ZipEntry> = entries.iter().collect();
                sorted_entries.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));

                for entry in sorted_entries {
                    if is_comicinfo_xml(&entry.name) {
                        continue;
                    }
                    page_num += 1;
                    let ext = get_ext(&entry.name);
                    let new_name = format!("page_{:0>width$}", page_num, width = padding as usize);
                    // Preserve extension.
                    let full_name = format!("{}{}", new_name, to_upper_ext(&ext));
                    new_entries.push(zip_ops::ZipEntry {
                        name: full_name,
                        data: entry.data.clone(),
                    });
                }
            }
            Err(e) => return Err(format!("Cannot read {}: {}", cbz_path.display(), e)),
        }
    }

    if generate_comicinfo {
        // Derive the volume title and number from the output filename ("Title V001.cbz").
        let stem = output_path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or_default();
        let title = stem.split_whitespace().next().unwrap_or_default().to_string();
        let vol_num: i32 = output_path
            .file_stem()
            .and_then(|s| s.to_str())
            .and_then(|s| s.rsplit_once(' '))
            .and_then(|(_, t)| t.strip_prefix('V'))
            .and_then(|v| v.parse::<i32>().ok())
            .unwrap_or(0);
        let mut ci = crate::comicinfo_xml::default_comicinfo();
        ci.title = title;
        ci.volume = vol_num;
        ci.count = page_num as i32;
        ci.page_count = page_num as i32;
        let xml = crate::comicinfo_xml::generate_comicinfo_xml(&ci);
        new_entries.push(crate::zip_ops::ZipEntry {
            name: crate::types::COMICINFO_XML.to_string(),
            data: xml,
        });
    }

    // Write ZIP entirely in RAM.
    zip_ops::write_zip_from_entries(output_path, &new_entries)
        .map_err(|e| format!("Failed to write: {}", e))?;

    Ok(page_num as usize)
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
// Merge planning and execution
// ---------------------------------------------------------------------------

/// Build the per-series merge plans (Phase 1).
///
/// Shared by `merge_chapters` and `merge_chapters_with_progress` so all three
/// knobs apply in exactly one place. Mirrors the Python reference:
///
/// - `chapters_list` (e.g. `[5, 6, 3]`) pins exact per-volume chapter counts and
///   drives the volume count directly; volumes still numbered from the next tag.
/// - `cpv_override` fixes chapters-per-volume instead of auto-calculating from
///   existing volumes (`(lowest_chapter-1)/num_volumes`, defaulting to 7).
/// - `force` appends any leftover chapters to the *last* volume once batches are
///   laid out.
///
/// Returns the same `(series_name, cpv, next_vol, num_new_volumes, volumes)`
/// tuple shape the execution loops already consume; `cpv` is `-1` for a pinned
/// custom chapter list (no meaningful average).
fn plan_series(
    dir: &Path,
    chapters: &[ChapterFile],
    volumes: &[VolumeFile],
    force: bool,
    chapters_list: Option<Vec<usize>>,
    cpv_override: Option<f64>,
) -> Vec<(String, f64, i32, usize, Vec<VolumeSpec>)> {
    let mut series_map: std::collections::HashMap<String, Vec<ChapterFile>> = std::collections::HashMap::new();
    for ch in chapters {
        series_map.entry(ch.series.clone()).or_default().push(ch.clone());
    }
    let mut volume_map: std::collections::HashMap<String, Vec<VolumeFile>> = std::collections::HashMap::new();
    for vo in volumes {
        volume_map.entry(vo.series.clone()).or_default().push(vo.clone());
    }

    // Sorted union of series names.
    let mut all_series: Vec<String> = series_map.keys().chain(volume_map.keys())
        .cloned().collect();
    all_series.sort();

    let mut plans: Vec<(String, f64, i32, usize, Vec<VolumeSpec>)> = Vec::new();
    for series_name in &all_series {
        let ch_list = series_map.get(series_name).cloned().unwrap_or_default();
        if ch_list.is_empty() { continue; }

        let vo_list = volume_map.get(series_name).cloned().unwrap_or_default();
        let num_chapters = ch_list.len();

        if chapters_list.is_some() {
            let list = chapters_list.as_ref().unwrap();
            let total_requested: usize = list.iter().sum();
            // Python exits with code 1 here; rust-core just creates no volumes
            // for this series rather than aborting the whole batch.
            if total_requested > num_chapters { continue; }

            let next_vol = if vo_list.is_empty() { 1i32 } else { max_volume_number(&vo_list) + 1 };
            let mut volumes: Vec<VolumeSpec> = Vec::new();
            let mut ch_index = 0usize;
            for (vol_idx, &count) in list.iter().enumerate() {
                if ch_index + count > num_chapters { break; }
                let vol_num = next_vol + vol_idx as i32;
                let output_path = dir.join(format!("{} V{:03}.cbz", series_name, vol_num));
                let batch: Vec<PathBuf> = ch_list[ch_index..ch_index + count]
                    .iter().map(|ch| ch.path.clone()).collect();
                volumes.push(VolumeSpec { output_path, chapter_paths: batch, num_pages: 0 });
                ch_index += count;
            }

            if !volumes.is_empty() {
                plans.push((series_name.clone(), -1.0, next_vol, volumes.len(), volumes));
            }
        } else {
            let chapters_per_volume = match cpv_override {
                Some(o) => o,
                None if vo_list.is_empty() => 7.0,
                None => {
                    let lowest_chapter = ch_list.first().map(|c| c.chapter_num).unwrap_or(1);
                    (lowest_chapter - 1) as f64 / vo_list.len() as f64
                }
            };

            if chapters_per_volume < 1.0 { continue; }

            let next_vol = if vo_list.is_empty() { 1i32 } else { max_volume_number(&vo_list) + 1 };
            let num_new_volumes = (num_chapters as f64 / chapters_per_volume) as usize;
            if num_new_volumes == 0 { continue; }

            let mut volumes: Vec<VolumeSpec> = Vec::new();
            let mut ch_index = 0usize;
            for vol_idx in 0..num_new_volumes {
                let vol_num = next_vol + vol_idx as i32;
                let output_path = dir.join(format!("{} V{:03}.cbz", series_name, vol_num));
                let start = ch_index;
                let end = cmp::min(ch_index + chapters_per_volume as usize, num_chapters);
                if start >= end { break; }
                let batch: Vec<PathBuf> = ch_list[start..end].iter().map(|ch| ch.path.clone()).collect();
                volumes.push(VolumeSpec { output_path, chapter_paths: batch, num_pages: 0 });
                ch_index = end;
            }

            // force: absorb the leftover chapters into the last volume so nothing is dropped.
            let remaining = num_chapters - ch_index;
            if remaining > 0 && force {
                let per_volumes = chapters_per_volume as usize;
                if let Some(last) = volumes.last_mut() {
                    let start = ch_index.saturating_sub(per_volumes);
                    last.chapter_paths = ch_list[start..ch_index + remaining]
                        .iter().map(|ch| ch.path.clone()).collect();
                }
            }

            if !volumes.is_empty() {
                plans.push((series_name.clone(), chapters_per_volume, next_vol, volumes.len(), volumes));
            }
        }
    }

    plans
}

// ---------------------------------------------------------------------------
// Merge planning and execution
// ---------------------------------------------------------------------------

/// Merge chapter CBZ files into volumes.
///
/// `chapter_start` / `chapter_end` optionally restrict the chapters that are
/// considered (inclusive); `None` means unbounded on that side. When
/// `generate_comicinfo` is true each output volume embeds a generated
/// `ComicInfo.xml`.
pub fn merge_chapters(
    dir: &Path,
    delete: bool,
    force: bool,
    chapters_list: Option<Vec<usize>>,
    cpv_override: Option<f64>,
    chapter_start: Option<usize>,
    chapter_end: Option<usize>,
    generate_comicinfo: bool,
) -> MergeResults {
    let progress = None; // CLI mode — no progress callback needed

    report_service_start(progress, "Merging", 1);

    let (chapters0, volumes) = parse_cbz_files(dir);
    let chapters = filter_chapter_range(&chapters0, chapter_start, chapter_end);

    if chapters.is_empty() {
        return vec![SeriesMergeResult {
            series_name: String::new(),
            volumes_created: 0,
            total_pages: 0,
            volumes: Vec::new(),
            error_msg: "No chapter files found".to_string(),
        }];
    }

    // Group by series.
    let mut series_map: std::collections::HashMap<String, Vec<ChapterFile>> = std::collections::HashMap::new();
    for ch in &chapters {
        series_map.entry(ch.series.clone()).or_default().push(ch.clone());
    }

    let mut volume_map: std::collections::HashMap<String, Vec<VolumeFile>> = std::collections::HashMap::new();
    for vo in &volumes {
        volume_map.entry(vo.series.clone()).or_default().push(vo.clone());
    }

    // Phase-1 plan for all series (force / chapters list / manual CPV handled in one place).
    let series_plans = plan_series(dir, &chapters, &volumes, force, chapters_list, cpv_override);

    // Execute merges.
    let mut results: Vec<SeriesMergeResult> = Vec::new();
    let total_series = series_plans.len();
    for (s_idx, (series_name, _cpv, _next_vol, num_volumes, volumes)) in series_plans.iter().enumerate() {
        report_service_progress(progress, "Merging", series_name.as_str(), s_idx, total_series);

        let mut total_pages = 0usize;
        let mut vol_results: Vec<MergeVolumeResult> = Vec::new();
        for vol in volumes {
            match merge_cbz_files(&vol.chapter_paths, &vol.output_path, generate_comicinfo) {
                Ok(page_count) => {
                    total_pages += page_count;
                    // Delete source chapters after successful merge.
                    if delete {
                        for ch_path in &vol.chapter_paths {
                            std::fs::remove_file(ch_path).ok();
                        }
                    }
                    vol_results.push(MergeVolumeResult {
                        title: vol.output_path.file_name()
                            .unwrap_or_default().to_string_lossy().to_string(),
                        output_path: vol.output_path.clone(),
                        chapters: vol.chapter_paths.clone(),
                    });
                }
                Err(e) => {
                    results.push(SeriesMergeResult {
                        series_name: series_name.clone(),
                        volumes_created: 0,
                        total_pages: 0,
                        volumes: Vec::new(),
                        error_msg: format!("{}: {}", series_name, e),
                    });
                    continue;
                }
            }
        }

        results.push(SeriesMergeResult {
            series_name: series_name.clone(),
            volumes_created: *num_volumes,
            total_pages,
            volumes: vol_results,
            error_msg: String::new(),
        });
    }

    if let Some(ref cb) = progress {
        cb(100, "Complete");
    }

    results
}

/// Get the highest volume number from a list of volume files.
fn max_volume_number(volumes: &[VolumeFile]) -> i32 {
    volumes.iter().filter_map(|v| {
        v.volume_tag.strip_prefix('V')?.parse::<i32>().ok()
    }).max().unwrap_or(0)
}

/// Restrict chapters to those whose chapter number lies in `[start, end]`
/// (inclusive). `None` leaves that bound unbounded. Mirrors Lazarus
/// `TMergeOptions.ChapterStart / ChapterEnd`. Returns the same vector when no
/// restriction is requested so the caller can keep the parse result unchanged.
fn filter_chapter_range(
    chapters: &[ChapterFile],
    start: Option<usize>,
    end: Option<usize>,
) -> Vec<ChapterFile> {
    match (start, end) {
        (Some(s), Some(e)) => chapters
            .iter()
            .filter(|c| c.chapter_num as usize >= s && c.chapter_num as usize <= e)
            .cloned()
            .collect(),
        _ => chapters.to_vec(),
    }
}

/// Merge chapter CBZ files into volumes with progress callback.
pub fn merge_chapters_with_progress(
    dir: &Path,
    delete: bool,
    force: bool,
    chapters_list: Option<Vec<usize>>,
    cpv_override: Option<f64>,
    chapter_start: Option<usize>,
    chapter_end: Option<usize>,
    generate_comicinfo: bool,
    on_progress: Option<Box<dyn Fn(i32, &str) + Send + Sync>>,
) -> MergeResults {
    let progress = on_progress;

    if let Some(ref cb) = progress {
        cb(0, "Merging 0/0 files");
    }

    if progress.is_none() {
        return merge_chapters(
            dir,
            delete,
            force,
            chapters_list,
            cpv_override,
            chapter_start,
            chapter_end,
            generate_comicinfo,
        );
    }

    let cb = progress.as_ref().unwrap();

    let (chapters0, volumes) = parse_cbz_files(dir);
    let chapters = filter_chapter_range(&chapters0, chapter_start, chapter_end);

    if chapters.is_empty() {
        cb(0, "No chapter files found");
        return vec![SeriesMergeResult {
            series_name: String::new(),
            volumes_created: 0,
            total_pages: 0,
            volumes: Vec::new(),
            error_msg: "No chapter files found".to_string(),
        }];
    }

    // Group by series.
    let mut series_map: std::collections::HashMap<String, Vec<ChapterFile>> = std::collections::HashMap::new();
    for ch in &chapters {
        series_map.entry(ch.series.clone()).or_default().push(ch.clone());
    }

    let mut volume_map: std::collections::HashMap<String, Vec<VolumeFile>> = std::collections::HashMap::new();
    for vo in &volumes {
        volume_map.entry(vo.series.clone()).or_default().push(vo.clone());
    }

    // Phase-1 plan for all series (force / chapters list / manual CPV handled in one place).
    let series_plans = plan_series(dir, &chapters, &volumes, force, chapters_list, cpv_override);

    // Execute merges with progress.
    let mut results: Vec<SeriesMergeResult> = Vec::new();
    let total_series = series_plans.len();

    if total_series == 0 {
        cb(100, "Complete");
        return results;
    }

    for (s_idx, (series_name, _cpv, _next_vol, num_volumes, volumes)) in series_plans.iter().enumerate() {
        let pct = ((s_idx as i32) * 100) / total_series as i32;
        cb(pct, &format!("Merging {} ({}/{})", series_name, s_idx + 1, total_series));

        let mut total_pages = 0usize;
        let mut vol_results: Vec<MergeVolumeResult> = Vec::new();
        for vol in volumes {
            match merge_cbz_files(
                &vol.chapter_paths,
                &vol.output_path,
                generate_comicinfo,
            ) {
                Ok(page_count) => {
                    total_pages += page_count;
                    if delete {
                        for ch_path in &vol.chapter_paths {
                            std::fs::remove_file(ch_path).ok();
                        }
                    }
                    vol_results.push(MergeVolumeResult {
                        title: vol.output_path.file_name()
                            .unwrap_or_default().to_string_lossy().to_string(),
                        output_path: vol.output_path.clone(),
                        chapters: vol.chapter_paths.clone(),
                    });
                }
                Err(e) => {
                    results.push(SeriesMergeResult {
                        series_name: series_name.clone(),
                        volumes_created: 0,
                        total_pages: 0,
                        volumes: Vec::new(),
                        error_msg: format!("{}: {}", series_name, e),
                    });
                    continue;
                }
            }
        }

        results.push(SeriesMergeResult {
            series_name: series_name.clone(),
            volumes_created: *num_volumes,
            total_pages,
            volumes: vol_results,
            error_msg: String::new(),
        });
    }

    cb(100, "Complete");

    results
}
