use std::path::Path;
use crossbeam_channel;
use tauri::Emitter;

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
    app: tauri::AppHandle,
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

    // Set up progress channel
    let (tx, rx) = crossbeam_channel::bounded::<(i32, String)>(64);
    let rx_progress = std::sync::Arc::new(std::sync::Mutex::new(Some(rx)));

    {
        let app_for_thread = app.clone();
        std::thread::spawn(move || {
            while let Ok((pct, msg)) = rx_progress.lock().unwrap().as_mut().unwrap().recv() {
                let _ = app_for_thread.emit(
                    "progress",
                    crate::commands::ProgressEvent {
                        percent: if pct < 0 {
                            0
                        } else if pct > 100 {
                            100
                        } else {
                            pct as u8
                        },
                        message: msg,
                        phase: "merging".to_string(),
                    },
                );
            }
        });
    }

    let cb: Option<Box<dyn Fn(i32, &str) + Send + Sync>> = Some(Box::new(move |pct, msg| {
        let _ = tx.send((pct, msg.to_string()));
    }));

    // Call the merge service with progress callback
    let results = rust_core::merge::merge_chapters_with_progress(
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
        cb,
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
        for v in series.volumes {
            volumes.push(MergeVolumeInfo {
                title: v.title,
                output_path: v.output_path.to_string_lossy().to_string(),
                chapters: v.chapters.into_iter().map(|p| p.to_string_lossy().to_string()).collect(),
            });
        }
    }

    Ok(MergeResult {
        volumes_created: volumes,
        total_pages,
        error_msg,
    })
}
