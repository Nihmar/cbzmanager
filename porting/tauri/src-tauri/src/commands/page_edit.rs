use std::path::Path;
use base64::{Engine as _, engine::general_purpose::STANDARD};

#[tauri::command]
pub async fn page_load(file_path: String) -> Result<Vec<rust_core::types::PageState>, String> {
    let entries = rust_core::zip_ops::collect_zip_entries(Path::new(&file_path))
        .map_err(|e| e.to_string())?;

    Ok(entries
        .into_iter()
        .enumerate()
        .map(|(i, entry)| rust_core::types::PageState {
            name: entry.name.clone(),
            orig_name: entry.name.clone(),
            gone: false,
            orig_index: i as i32,
            data: Some(STANDARD.encode(&entry.data)),
        })
        .collect())
}

#[tauri::command]
pub async fn page_save(
    pages: Vec<rust_core::types::PageState>,
    file_path: String,
) -> Result<rust_core::types::SaveChangesResult, String> {
    // Convert frontend PageState → internal PageState (page_model module)
    let internal_pages: Vec<rust_core::page_model::PageState> = pages
        .iter()
        .map(|p| rust_core::page_model::PageState {
            orig_name: p.orig_name.clone(),
            name: p.name.clone(),
            data: p.data.as_ref().map(|b64| STANDARD.decode(b64).unwrap_or_default()),
            deleted: p.gone,
        })
        .collect();

    let model = rust_core::page_model::PageModel::from_pages(internal_pages);

    match rust_core::page_model::save_changes(&model, Path::new(&file_path)) {
        Ok(_) => Ok(rust_core::types::SaveChangesResult {
            success: true,
            error_msg: String::new(),
        }),
        Err(e) => Ok(rust_core::types::SaveChangesResult {
            success: false,
            error_msg: e,
        }),
    }
}
