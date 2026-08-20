use std::path::Path;

#[derive(serde::Serialize, Clone)]
pub struct MergeResult {
    pub volumes_created: Vec<MergeVolumeInfo>,
    pub total_pages: usize,
    pub error_msg: Option<String>,
}

#[derive(serde::Serialize, Clone)]
pub struct MergeVolumeInfo {
    pub title: String,
    pub output_path: String,
    pub chapters: Vec<String>,
}

#[tauri::command]
pub async fn cmd_merge(
    dir_path: String,
    force: bool,
    chapters: Option<String>,
    chapters_per_volume: Option<u32>,
    delete_source: bool,
) -> Result<MergeResult, String> {
    // Parse config from CLI arguments (mutual exclusion handled by caller)
    let config = match (chapters, chapters_per_volume) {
        (Some(ch), None) => {
            let nums: Vec<usize> = ch
                .split(',')
                .filter_map(|s| s.trim().parse().ok())
                .collect();
            Some(rust_core::types::MergeConfig::Chapters(nums))
        }
        (_, Some(cpv)) => Some(rust_core::types::MergeConfig::ChaptersPerVolume(cpv as usize)),
        _ => None,
    };

    // Call the merge service (force and chapter params are accepted but some are internal)
    let results = rust_core::merge::merge_chapters(
        Path::new(&dir_path),
        delete_source,
        force,
        config.as_ref().and_then(|c| match c {
            rust_core::types::MergeConfig::Chapters(nums) => Some(nums.clone()),
            _ => None,
        }),
        config.as_ref().and_then(|c| match c {
            rust_core::types::MergeConfig::ChaptersPerVolume(n) => Some(*n),
            _ => None,
        }),
    );

    // Convert local SeriesMergeResult -> our result type
    let mut volumes = Vec::new();
    let mut total_pages = 0;
    let mut error_msg: Option<String> = None;

    for series in results {
        if !series.error_msg.is_empty() && error_msg.is_none() {
            error_msg = Some(series.error_msg.clone());
        }
        total_pages += series.total_pages;
        // Note: volumes_created count is available but we'd need to track volume paths
        // from the actual output. For now report series name.
    }

    Ok(MergeResult {
        volumes_created: volumes,
        total_pages,
        error_msg,
    })
}
