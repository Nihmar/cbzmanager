use std::path::{Path, PathBuf};

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
pub async fn cmd_validate(dir_path: String) -> Result<Vec<FileValidationResult>, String> {
    let files = rust_core::helpers::collect_cbz_files(Path::new(&dir_path));

    if files.is_empty() {
        return Ok(Vec::new());
    }

    let file_names: Vec<&str> = files
        .iter()
        .filter_map(|f| f.file_name().and_then(|n| n.to_str()))
        .collect();

    // Quick validation (not deep)
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

    // Deep validation with parallel decode
    let results = rust_core::validate::validate_deep(Path::new(&dir_path), &files, actual_threads);

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
