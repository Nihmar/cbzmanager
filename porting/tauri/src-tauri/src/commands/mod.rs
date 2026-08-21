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

#[derive(serde::Serialize, Clone)]
pub struct ProgressEvent {
    pub percent: u8,
    pub message: String,
    pub phase: String,
}

