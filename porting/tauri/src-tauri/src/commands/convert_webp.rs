use std::path::{Path, PathBuf};
use crossbeam_channel;
use tauri::Emitter;

#[derive(serde::Serialize, Clone)]
pub struct ConvertWebpResult {
    pub dir_path: String,
    pub converted: Vec<String>,
    pub skipped: Vec<String>,
}

#[tauri::command]
pub async fn cmd_convert_webp(
    app: tauri::AppHandle,
    dir_path: String,
    _delete_source: bool,
    threads: Option<u32>,
) -> Result<ConvertWebpResult, String> {
    let files = rust_core::helpers::collect_cbz_files(Path::new(&dir_path));

    if files.is_empty() {
        return Ok(ConvertWebpResult {
            dir_path,
            converted: Vec::new(),
            skipped: Vec::new(),
        });
    }

    let cpu_count = rust_core::helpers::online_cpu_count();
    let threads_val = threads.unwrap_or(0).max(1) as usize;
    let actual_threads = if threads_val == 0 || threads_val > rust_core::types::MAX_WEBP_THREADS {
        std::cmp::min(cpu_count, rust_core::types::MAX_WEBP_THREADS)
    } else {
        threads_val
    };

    // Set up progress channel — workers send (percent, message), background task forwards to Tauri.
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
                        phase: "converting".to_string(),
                    },
                );
            }
        });
    }

    let cb: Option<Box<dyn Fn(i32, &str) + Send + Sync>> = Some(Box::new(move |pct, msg| {
        let _ = tx.send((pct, msg.to_string()));
    }));

    // Delete source option: if true, original is deleted; if false, renamed to "_OLD.cbz" backup.
    let results = rust_core::convert_webp::convert_webp_with_progress(
        Path::new(&dir_path),
        &files,
        actual_threads,
        _delete_source,
        cb,
    );

    let converted: Vec<String> = results
        .iter()
        .filter(|r| r.converted)
        .map(|r| r.file_name.clone())
        .collect();

    let skipped: Vec<String> = results
        .iter()
        .filter(|r| !r.converted && r.error_msg.is_empty())
        .map(|r| r.file_name.clone())
        .collect();

    Ok(ConvertWebpResult {
        dir_path,
        converted,
        skipped,
    })
}
