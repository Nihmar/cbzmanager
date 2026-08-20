use std::path::{Path, PathBuf};

#[derive(serde::Serialize, Clone)]
pub struct CbrConversionResult {
    pub input: String,
    pub output: Option<String>,
    pub ok: bool,
    pub error: Option<String>,
}

#[tauri::command]
pub async fn cmd_cbr_to_cbz(
    dir_path: String,
    _delete_source: bool,
    threads: Option<u32>,
) -> Result<Vec<CbrConversionResult>, String> {
    if !rust_core::cbr_reader::cbr_supported() {
        return Err("CBR support not available: libarchive not found".to_string());
    }

    let files = rust_core::helpers::collect_cbr_files(Path::new(&dir_path));

    if files.is_empty() {
        return Ok(Vec::new());
    }

    let cpu_count = rust_core::helpers::online_cpu_count();
    let threads_val = threads.unwrap_or(0).max(1) as usize;
    let actual_threads = std::cmp::min(cpu_count, rust_core::types::MAX_CBR_THREADS);

    // convert_cbr_to_cbz doesn't expose delete_source parameter - that's handled elsewhere
    let results = rust_core::cbr_convert::convert_cbr_to_cbz(Path::new(&dir_path), &files, actual_threads, false);

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
