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

    // GAPS 1.4: cap the worker count at MAX_CBR_THREADS (mirrors
    // uservicecomicinfo.pas Min(OnlineCpuCount, MAX_CBR_CONVERT_THREADS)).
    let actual_threads = std::cmp::min(
        threads.unwrap_or(0).max(1) as usize,
        rust_core::types::MAX_CBR_THREADS,
    );

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

// Read an archive's ComicInfo.xml and return it as parsed metadata, or None when the
// archive has no ComicInfo.xml entry. Used to pre-fill TdlgComicInfoEditor-style forms.
#[tauri::command]
pub async fn cmd_get_comicinfo(
    file_path: String,
) -> Result<Option<rust_core::comicinfo_xml::ComicInfo>, String> {
    use rust_core::zip_ops;

    let entries = zip_ops::collect_zip_entries_all(Path::new(&file_path))
        .map_err(|e| e.to_string())?;

    for entry in &entries {
        if entry.is_comicinfo() {
            let ci = rust_core::comicinfo_xml::parse_comicinfo_xml(&entry.data);
            return Ok(Some(ci));
        }
    }

    Ok(None)
}

// Update the ComicInfo.xml inside a single CBZ archive. As with remove/scan, this is a
// single-file change committed immediately (not staged in the page model). The edit runs
// entirely in RAM: every entry is read back out, any existing ComicInfo.xml is dropped, and
// a fresh one is written back first — GenerateComicInfoXML omits empty/unset fields.
#[tauri::command]
pub async fn cmd_edit_comicinfo(
    file_path: String,
    ci: rust_core::comicinfo_xml::ComicInfo,
) -> Result<ComicInfoResult, String> {
    use rust_core::zip_ops::{self, ZipEntry};

    let mut entries = zip_ops::collect_zip_entries_all(Path::new(&file_path))
        .map_err(|e| e.to_string())?;

    // Drop any existing ComicInfo.xml (case-insensitive) before re-adding.
    entries.retain(|e| !e.is_comicinfo());

    let xml = rust_core::comicinfo_xml::generate_comicinfo_xml(&ci);
    entries.insert(0, ZipEntry::new("ComicInfo.xml", xml));

    zip_ops::write_zip_from_entries(Path::new(&file_path), &entries)
        .map_err(|e| e.to_string())?;

    Ok(ComicInfoResult {
        file_name: Path::new(&file_path)
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_default(),
        found: true,
        message: Some("ComicInfo.xml updated".to_string()),
    })
}
