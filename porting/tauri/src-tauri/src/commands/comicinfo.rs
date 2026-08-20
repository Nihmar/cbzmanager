use std::path::Path;

#[derive(serde::Serialize, Clone)]
pub struct ComicInfoResult {
    pub file_name: String,
    pub found: bool,
    pub message: Option<String>,
}

#[tauri::command]
pub async fn cmd_scan_comicinfo(dir_path: String) -> Result<Vec<ComicInfoResult>, String> {
    let files = rust_core::helpers::collect_cbz_files(Path::new(&dir_path));

    if files.is_empty() {
        return Ok(Vec::new());
    }

    let file_names: Vec<&str> = files
        .iter()
        .filter_map(|f| f.file_name().and_then(|n| n.to_str()))
        .collect();

    let results = rust_core::comicinfo::scan(Path::new(&dir_path), &file_names);

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

    let results = rust_core::comicinfo::remove(Path::new(&dir_path), &file_names, backup, actual_threads);

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
