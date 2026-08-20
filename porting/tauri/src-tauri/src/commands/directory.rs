use rust_core::zip_ops;
use rust_core::types::DirEntry;

#[tauri::command]
pub async fn list_directory(dir_path: String) -> Result<Vec<DirEntry>, String> {
    let files = rust_core::helpers::collect_cbz_files(&std::path::Path::new(&dir_path));
    let mut result = Vec::new();

    for file in &files {
        let name = file
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("")
            .to_string();
        let ext = file.extension().and_then(|e| e.to_str()).unwrap_or("").to_string();

        let thumbnail = match zip_ops::first_image_data(file) {
            Ok(Some(data)) => match rust_core::image_util::generate_thumbnail(&data, 320) {
                Ok(b64) => Some(b64),
                Err(_) => None,
            },
            _ => None,
        };

        result.push(DirEntry {
            name,
            is_dir: false,
            ext,
            thumbnail,
        });
    }

    // Also collect CBR files if supported
    if rust_core::cbr_reader::cbr_supported() {
        let cbr_files = rust_core::helpers::collect_cbr_files(&std::path::Path::new(&dir_path));
        for file in &cbr_files {
            let name = file
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("")
                .to_string();
            let ext = file.extension().and_then(|e| e.to_str()).unwrap_or("").to_string();

            let thumbnail = match rust_core::cbr_reader::collect_cbr_entries(file) {
                Ok(entries) => entries.first().map(|entry| {
                    // entry is (String, Vec<u8>) - tuple
                    match rust_core::image_util::generate_thumbnail(&entry.1, 320) {
                        Ok(b64) => Some(b64),
                        Err(_) => None,
                    }
                }),
                Err(_) => None,
            }.flatten();

            result.push(DirEntry {
                name,
                is_dir: false,
                ext,
                thumbnail,
            });
        }
    }

    // Sort by name (case-insensitive)
    result.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));

    Ok(result)
}
