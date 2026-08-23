use std::path::Path;
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
    // GAPS 1.5 — quality knob (0 / None => the reference default q75).
    quality: Option<u32>,
    // GAPS 1.6 — keep pages already in WebP without re-encoding.
    skip_existing: Option<bool>,
    // GAPS 1.7 — filter ComicInfo.xml out of the output.
    remove_comicinfo: Option<bool>,
    // GAPS 1.8 — rename surviving pages sequentially (page_NNNN.ext).
    renumber: Option<bool>,
    // GAPS 1.9 — only replace a page when its WebP encoding is smaller.
    replace_only_if_smaller: Option<bool>,
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
    // GAPS 1.5–1.9: build ConvertOptions from the caller-supplied knobs, falling back
    // to the reference defaults for anything left unset (mirrors Lazarus checkbox state).
    let base = rust_core::convert_webp::ConvertOptions::default();
    let options = rust_core::convert_webp::ConvertOptions {
        remove_comicinfo: remove_comicinfo.unwrap_or(base.remove_comicinfo),
        renumber_pages: renumber.unwrap_or(base.renumber_pages),
        replace_only_if_smaller: replace_only_if_smaller.unwrap_or(base.replace_only_if_smaller),
        skip_existing_webp: skip_existing.unwrap_or(base.skip_existing_webp),
    };
    let quality_value = quality.unwrap_or(0); // 0 => use the server default (q75).

    let results = rust_core::convert_webp::convert_webp_with_progress(
        Path::new(&dir_path),
        &files,
        actual_threads,
        _delete_source,
        quality_value, // 0 => use the server default (q75).
        cb,
        options,
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
