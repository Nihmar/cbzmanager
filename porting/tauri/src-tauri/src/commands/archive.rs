use rust_core::zip_ops;
use std::path::Path;

#[derive(serde::Serialize, Clone)]
pub struct ArchiveEntry {
    pub name: String,
    pub size: u64,
}

#[tauri::command]
pub async fn list_entries(file_path: String) -> Result<Vec<ArchiveEntry>, String> {
    let entries = zip_ops::get_entry_names(Path::new(&file_path))
        .map_err(|e| e.to_string())?;

    Ok(entries
        .into_iter()
        .map(|name| ArchiveEntry {
            name,
            size: 0,
        })
        .collect())
}

#[tauri::command]
pub async fn read_entry(file_path: String, name: String) -> Result<Vec<u8>, String> {
    zip_ops::read_entry(Path::new(&file_path), &name).map_err(|e| e.to_string())
}

#[derive(serde::Serialize, Clone)]
pub struct FirstImageResult {
    pub name: Option<String>,
    pub thumbnail: Option<String>,
}

#[tauri::command]
pub async fn first_image(file_path: String) -> Result<FirstImageResult, String> {
    let path = Path::new(&file_path);

    let name = zip_ops::first_image_name(path).map_err(|e| e.to_string())?;
    let name = match name {
        Some(n) => n,
        None => return Ok(FirstImageResult { name: None, thumbnail: None }),
    };

    let data = zip_ops::read_entry(path, &name).map_err(|e| e.to_string())?;

    let thumbnail = match rust_core::image_util::generate_thumbnail(&data, 320) {
        Ok(b64) => Some(b64),
        Err(_) => None,
    };

    Ok(FirstImageResult {
        name: Some(name),
        thumbnail,
    })
}
