use std::path::{Path, PathBuf};
use crossbeam_channel;
use tauri::Emitter;

#[derive(serde::Serialize, Clone)]
pub struct CbrConversionResult {
    pub input: String,
    pub output: Option<String>,
    pub ok: bool,
    pub error: Option<String>,
}

#[tauri::command]
pub async fn cmd_cbr_to_cbz(
    app: tauri::AppHandle,
    dir_path: String,
    _delete_source: bool,
    threads: Option<u32>,
) -> Result<Vec<CbrConversionResult>, String> {
    if !rust_core::cbr_reader::cbr_supported() {
        return Err("CBR support not available: libarchive not found".to_string());
    }

    // Note: _delete_source is accepted but rust-core CBR conversion always creates backup.
    // delete-source support for CBR would require threading the parameter through process_cbr.
    let files = rust_core::helpers::collect_cbr_files(Path::new(&dir_path));

    if files.is_empty() {
        return Ok(Vec::new());
    }

    let cpu_count = rust_core::helpers::online_cpu_count();
    let threads_val = threads.unwrap_or(0).max(1) as usize;
    let actual_threads = std::cmp::min(cpu_count, rust_core::types::MAX_CBR_THREADS);

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
                        phase: "cbr_convert".to_string(),
                    },
                );
            }
        });
    }

    let cb: Option<Box<dyn Fn(i32, &str) + Send + Sync>> = Some(Box::new(move |pct, msg| {
        let _ = tx.send((pct, msg.to_string()));
    }));

    // convert_cbr_to_cbz skips existing is not applicable for batch mode
    let results = rust_core::cbr_convert::convert_cbr_to_cbz_with_progress(
        Path::new(&dir_path),
        &files,
        actual_threads,
        false, // skip_existing
        cb,
    );

    Ok(results
        .into_iter()
        .map(|r| CbrConversionResult {
            input: r.file_name,
            output: None, // Local type doesn't track output path
            ok: r.converted,
            error: if !r.error_msg.is_empty() { Some(r.error_msg) } else { None },
        })
        .collect())
}
