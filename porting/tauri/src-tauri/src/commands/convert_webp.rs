use std::path::{Path, PathBuf};

#[derive(serde::Serialize, Clone)]
pub struct ConvertWebpResult {
    pub dir_path: String,
    pub converted: Vec<String>,
    pub skipped: Vec<String>,
}

#[tauri::command]
pub async fn cmd_convert_webp(
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

    let results = rust_core::convert_webp::convert_webp(Path::new(&dir_path), &files, actual_threads);

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
