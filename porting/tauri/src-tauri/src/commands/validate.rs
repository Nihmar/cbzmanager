use std::path::Path;
use crossbeam_channel;
use tauri::Emitter;

#[derive(serde::Serialize, Clone)]
pub struct ImageCheckResult {
    pub filename: String,
    pub ok: bool,
    pub errors: Vec<String>,
}

#[derive(serde::Serialize, Clone)]
pub struct FileValidationResult {
    pub file_name: String,
    pub valid: bool,
    pub image_count: u32,
    pub error_msg: Option<String>,
    pub image_checks: Vec<ImageCheckResult>,
}

#[tauri::command]
pub async fn cmd_validate(
    _app: tauri::AppHandle,
    dir_path: String,
) -> Result<Vec<FileValidationResult>, String> {
    let files = rust_core::helpers::collect_cbz_files(Path::new(&dir_path));

    if files.is_empty() {
        return Ok(Vec::new());
    }

    let file_names: Vec<&str> = files
        .iter()
        .filter_map(|f| f.file_name().and_then(|n| n.to_str()))
        .collect();

    // Quick validation (not deep) - no progress callback needed for quick validate
    let results = rust_core::validate::validate(Path::new(&dir_path), &file_names);

    Ok(results
        .into_iter()
        .map(|r| FileValidationResult {
            file_name: r.file_name,
            valid: r.valid,
            image_count: r.image_count as u32,
            error_msg: if r.error_msg.is_empty() { None } else { Some(r.error_msg) },
            image_checks: Vec::new(), // Quick validation doesn't include per-image checks
        })
        .collect())
}

#[tauri::command]
pub async fn cmd_validate_deep(
    app: tauri::AppHandle,
    dir_path: String,
    threads: Option<u32>,
) -> Result<Vec<FileValidationResult>, String> {
    let files = rust_core::helpers::collect_cbz_files(Path::new(&dir_path));

    if files.is_empty() {
        return Ok(Vec::new());
    }

    let cpu_count = rust_core::helpers::online_cpu_count();
    let threads_val = threads.unwrap_or(0).max(1) as usize;
    let actual_threads = if threads_val == 0 || threads_val > rust_core::types::MAX_WEBP_THREADS {
        std::cmp::min(cpu_count, rust_core::types::MAX_WEBP_THREADS)
    } else {
        threads_val
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
                        phase: "validating".to_string(),
                    },
                );
            }
        });
    }

    let cb: Option<Box<dyn Fn(i32, &str) + Send + Sync>> = Some(Box::new(move |pct, msg| {
        let _ = tx.send((pct, msg.to_string()));
    }));

    // Deep validation with parallel decode and progress
    let results = rust_core::validate::validate_deep_with_progress(
        Path::new(&dir_path),
        &files,
        actual_threads,
        cb,
    );

    Ok(results
        .into_iter()
        .map(|r| FileValidationResult {
            file_name: r.file_name,
            valid: r.valid,
            image_count: r.image_count as u32,
            error_msg: if r.error_msg.is_empty() { None } else { Some(r.error_msg) },
            image_checks: r
                .image_checks
                .into_iter()
                .map(|c| ImageCheckResult {
                    filename: c.filename,
                    ok: c.ok,
                    errors: c.errors,
                })
                .collect(),
        })
        .collect())
}
