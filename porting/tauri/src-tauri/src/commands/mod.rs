pub mod archive;
pub mod directory;
pub mod validate;
pub mod convert_webp;
pub mod merge;
pub mod cbr_to_cbz;
pub mod comicinfo;
pub mod page_edit;
pub mod settings;
pub mod batch_edit;

use tauri::Emitter;

#[derive(serde::Serialize, Clone)]
pub struct ProgressEvent {
    pub percent: u8,
    pub message: String,
    pub phase: String,
}

#[tauri::command]
pub fn emit_progress(app: tauri::AppHandle, percent: u8, message: String, phase: String) {
    let _ = app.emit("progress", ProgressEvent { percent, message, phase });
}
