/// Shared service-layer types for CBZ Manager.
///
/// Replaces `uservicebase.pas`: progress callbacks, validation result types,
/// page-edit model types, and archive-type enumeration.

/// ---------------------------------------------------------------------------
/// Constants
/// ---------------------------------------------------------------------------

/// Suffix that identifies a backup copy of a CBZ ("manga.cbz" → "manga_OLD.cbz").
pub const BACKUP_SUFFIX: &str = "_OLD.cbz";

/// File extension identifying a comic archive (CBZ).
pub const CBZ_EXT: &str = ".cbz";

/// File extension identifying a RAR comic archive (CBR).
pub const CBR_EXT: &str = ".cbr";

/// Maximum parallel workers for WebP conversion pool (each holds one full-res image).
pub const MAX_WEBP_THREADS: usize = 8;

/// Maximum parallel workers for CBR→CBZ conversion pool (each holds one decompressed archive).
pub const MAX_CBR_THREADS: usize = 4;

/// Name of the ComicInfo.xml metadata entry inside a CBZ.
pub const COMICINFO_XML: &str = "ComicInfo.xml";

/// Fixed zero-padding width for page renumbering (e.g. "page_0001.jpg").
pub const PAGE_PAD_DEFAULT: usize = 4;

/// Minimum zero-padding width for count-derived page numbering.
pub const PAGE_PAD_MIN: usize = 3;

/// ---------------------------------------------------------------------------
/// Progress callbacks
/// ---------------------------------------------------------------------------

/// Progress-reporting callback. Called with a percentage (0–100) and a
/// human-readable description of the current step.
///
/// In Tauri commands this is replaced by event emission; in CLI mode the
/// callback prints to stdout. Services that run on rayon threads wrap the
/// callback in a `Mutex` to serialize concurrent progress reports.
pub type ServiceProgressFn = dyn Fn(i32, &str) + Send + Sync;

/// ---------------------------------------------------------------------------
/// Validation result types
/// ---------------------------------------------------------------------------

/// Per-image validation result.
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct ImageCheck {
    /// Entry name inside the archive.
    pub entry_name: String,
    /// Whether the image decoded successfully.
    pub valid: bool,
    /// Human-readable error message when `valid` is false.
    pub error_msg: String,
}

/// Array of per-image check results.
pub type ImageChecks = Vec<ImageCheck>;

/// Validation result for a single CBZ file.
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct FileValidationResult {
    /// Base name of the checked file (no path).
    pub file_name: String,
    /// True if the file is a well-formed CBZ with at least one readable image.
    pub valid: bool,
    /// Number of successfully decoded images (deep mode) or total image entries (quick).
    pub image_count: usize,
    /// Human-readable description when `valid` is false.
    pub error_msg: String,
    /// Per-image detail records; populated only by ValidateDeep.
    pub image_checks: ImageChecks,
}

/// Dynamic array of per-file validation entries.
pub type FileValidationResults = Vec<FileValidationResult>;

/// ---------------------------------------------------------------------------
/// Conversion result types
/// ---------------------------------------------------------------------------

/// Result for a single WebP conversion operation.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ConversionResult {
    /// Files that were converted to WebP.
    pub converted: Vec<std::path::PathBuf>,
    /// Files that were skipped (already optimal or not convertible).
    pub skipped: Vec<std::path::PathBuf>,
}

/// ---------------------------------------------------------------------------
/// Merge result types
/// ---------------------------------------------------------------------------

/// A chapter file and its numeric sort key.
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct ChapterInfo {
    /// File name (bare, no directory).
    pub file_name: String,
    /// Chapter number extracted from the filename for sorting.
    pub chapter_number: usize,
    /// Series name extracted from the filename.
    pub series: String,
}

/// Array of chapter info records.
pub type ChapterArray = Vec<ChapterInfo>;

/// Merge configuration.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub enum MergeConfig {
    /// Specific chapters to merge (e.g. 1,3,5).
    Chapters(Vec<usize>),
    /// Chapters per volume.
    ChaptersPerVolume(usize),
}

/// A single output volume produced by a merge operation.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct MergeVolume {
    /// Title of the resulting volume (e.g. "Series Name V01").
    pub title: String,
    /// Output file path for the merged CBZ.
    pub output_path: std::path::PathBuf,
    /// Source chapter files included in this volume.
    pub chapters: Vec<std::path::PathBuf>,
    /// Optional ComicInfo.xml content to embed in the volume.
    pub comicinfo_xml: Option<Vec<u8>>,
}

/// Overall merge result: one entry per generated volume.
pub type MergeResults = Vec<MergeVolume>;

/// ---------------------------------------------------------------------------
/// ComicInfo scan/remove result types
/// ---------------------------------------------------------------------------

/// Whether to scan for or remove ComicInfo.xml entries.
#[derive(Debug, Clone, Copy, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum ComicInfoAction {
    Scan,
    Remove,
}

/// Result for a single file in a ComicInfo operation.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ComicInfoResult {
    /// Base name of the checked file.
    pub file_name: String,
    /// Whether a ComicInfo.xml was found (scan) or removed (remove).
    pub found: bool,
    /// Human-readable description.
    pub message: String,
}

/// Array of per-file ComicInfo results.
pub type ComicInfoResults = Vec<ComicInfoResult>;

/// ---------------------------------------------------------------------------
/// CBR conversion result types
/// ---------------------------------------------------------------------------

/// Result for a single CBR→CBZ conversion.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct CbrConversionResult {
    /// Input .cbr file path.
    pub input: std::path::PathBuf,
    /// Output .cbz file path (only set on success).
    pub output: Option<std::path::PathBuf>,
    /// Whether the conversion succeeded.
    pub ok: bool,
    /// Error description when `ok` is false.
    pub error: Option<String>,
}

/// Array of per-file CBR conversion results.
pub type CbrConversionResults = Vec<CbrConversionResult>;

/// ---------------------------------------------------------------------------
/// Page edit model types
/// ---------------------------------------------------------------------------

/// Types of changes tracked for undo.
#[derive(Debug, Clone, Copy, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum ChangeKind {
    /// The page was removed from the list.
    Deleted,
    /// The page was reordered to a different position.
    Moved,
    /// The page's image content was replaced (resize/colour/split).
    Edited,
}

/// A single undo/redo change record.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct Change {
    /// The type of change.
    pub kind: ChangeKind,
    /// The entry name affected (matches TPageState.orig_name).
    pub page_name: String,
}

/// In-memory state for a single page in the editing model.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct PageState {
    /// Current entry name inside the CBZ (may differ from orig_name after rename).
    pub name: String,
    /// Original entry name at open time — used as the lookup key during save.
    pub orig_name: String,
    /// When true the page is marked for deletion and is skipped on save.
    pub gone: bool,
    /// Original 0-based position at open time (preserved for undo reference).
    pub orig_index: i32,
    /// Raw image data for inserted or edited pages (None = unchanged archive page).
    pub data: Option<Vec<u8>>,
}

/// Dynamic array of TPageState — the entire page list of a CBZ.
pub type PageStates = Vec<PageState>;

/// Dynamic array of TChange — undo/redo stack.
pub type Changes = Vec<Change>;

/// Outcome of a background save operation.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct SaveChangesResult {
    /// Whether the CBZ was rewritten without error.
    pub success: bool,
    /// Human-readable error description when success is false.
    pub error_msg: String,
}

/// ---------------------------------------------------------------------------
/// Directory entry for file browser
/// ---------------------------------------------------------------------------

/// An entry in a directory listing (file or subdirectory).
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct DirEntry {
    /// Base name of the entry.
    pub name: String,
    /// Whether this is a directory.
    pub is_dir: bool,
    /// File extension (lowercased), if any.
    pub ext: String,
    /// Thumbnail as base64-encoded JPEG (empty if not yet loaded).
    pub thumbnail: Option<String>,
}

/// ---------------------------------------------------------------------------
/// Utility types
/// ---------------------------------------------------------------------------

/// Archive type.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ArchiveType {
    Cbz,
    Cbr,
}
