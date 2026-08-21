use std::path::Path;
use crossbeam_channel;
use tauri::Emitter;

#[derive(serde::Serialize, Clone)]
pub struct ComicInfoResult {
    pub file_name: String,
    pub found: bool,
    pub message: Option<String>,
}

#[tauri::command]
pub async fn cmd_scan_comicinfo(
    app: tauri::AppHandle,
    dir_path: String,
) -> Result<Vec<ComicInfoResult>, String> {
    let files = rust_core::helpers::collect_cbz_files(Path::new(&dir_path));

    if files.is_empty() {
        return Ok(Vec::new());
    }

    let file_names: Vec<&str> = files
        .iter()
        .filter_map(|f| f.file_name().and_then(|n| n.to_str()))
        .collect();

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
                        phase: "comicinfo_scan".to_string(),
                    },
                );
            }
        });
    }

    let cb: Option<Box<dyn Fn(i32, &str) + Send + Sync>> = Some(Box::new(move |pct, msg| {
        let _ = tx.send((pct, msg.to_string()));
    }));

    let results = rust_core::comicinfo::scan_with_progress(Path::new(&dir_path), &file_names, cb);

    Ok(results
        .into_iter()
        .map(|r| ComicInfoResult {
            file_name: r.file_name,
            found: r.has_comicinfo,
            message: if r.has_comicinfo {
                Some("Found".to_string())
            } else if !r.error_msg.is_empty() {
                Some(r.error_msg)
            } else {
                None
            },
        })
        .collect())
}

#[tauri::command]
pub async fn cmd_remove_comicinfo(
    app: tauri::AppHandle,
    dir_path: String,
    backup: bool,
    threads: Option<u32>,
) -> Result<Vec<ComicInfoResult>, String> {
    let files = rust_core::helpers::collect_cbz_files(Path::new(&dir_path));

    if files.is_empty() {
        return Ok(Vec::new());
    }

    let file_names: Vec<&str> = files
        .iter()
        .filter_map(|f| f.file_name().and_then(|n| n.to_str()))
        .collect();

    let actual_threads = threads.unwrap_or(0).max(1) as usize;

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
                        phase: "comicinfo_remove".to_string(),
                    },
                );
            }
        });
    }

    let cb: Option<Box<dyn Fn(i32, &str) + Send + Sync>> = Some(Box::new(move |pct, msg| {
        let _ = tx.send((pct, msg.to_string()));
    }));

    let results = rust_core::comicinfo::remove_with_progress(
        Path::new(&dir_path),
        &file_names,
        backup,
        actual_threads,
        cb,
    );

    Ok(results
        .into_iter()
        .map(|r| ComicInfoResult {
            file_name: r.file_name,
            found: r.removed || r.has_comicinfo,
            message: if r.removed {
                Some("Removed".to_string())
            } else if !r.error_msg.is_empty() {
                Some(r.error_msg)
            } else if r.has_comicinfo {
                Some("Present but not removed (error)".to_string())
            } else {
                None
            },
        })
        .collect())
}
