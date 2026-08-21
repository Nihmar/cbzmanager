/// ZIP read/write operations — entirely in RAM.
///
/// Replaces `uzipcore.pas` (CollectZipEntries, WriteZipFromEntriesDeflated)
/// and the collection/writing parts of `uzipeditor.pas`.
/// All operations use Vec<u8> buffers; no temp files on disk.

use std::io::{Read, Write};
use std::path::Path;

use zip::read::ZipArchive;
use zip::write::{FileOptions, ZipWriter};
use zip::CompressionMethod;

use crate::helpers::*;
use crate::types::*;

/// A single ZIP entry in memory.
/// Equivalent to Pascal's TZipEntryData (Name + Data as stream).
#[derive(Debug, Clone)]
pub struct ZipEntry {
    /// Entry name inside the archive (e.g. "page_0001.jpg" or "ComicInfo.xml").
    pub name: String,
    /// Raw entry data.
    pub data: Vec<u8>,
}

impl ZipEntry {
    /// Create a new entry from name and data.
    pub fn new(name: impl Into<String>, data: Vec<u8>) -> Self {
        Self {
            name: name.into(),
            data,
        }
    }

    /// Whether this entry is ComicInfo.xml (case-insensitive).
    pub fn is_comicinfo(&self) -> bool {
        is_comicinfo_xml(&self.name)
    }
}

/// Alias for Vec<ZipEntry> — replaces Pascal's TZipEntries.
pub type ZipEntries = Vec<ZipEntry>;

// ---------------------------------------------------------------------------
// CollectZipEntries
// ---------------------------------------------------------------------------

/// Read all entries from a CBZ into RAM, filtering out ComicInfo.xml.
///
/// Open the ZIP and read each entry's data into a Vec<u8>. Entries whose name
/// matches "ComicInfo.xml" (case-insensitive) are skipped entirely — they never
/// appear in the result.
pub fn collect_zip_entries(path: &Path) -> Result<ZipEntries> {
    let file = std::fs::File::open(path).map_err(|e| {
        Error::Io(format!("Failed to open {}: {}", path.display(), e))
    })?;
    let mut archive = ZipArchive::new(file).map_err(|e| {
        Error::InvalidZip(format!("Not a valid ZIP: {}", e))
    })?;

    let mut entries: Vec<ZipEntry> = Vec::with_capacity(archive.len());
    for i in 0..archive.len() {
        let mut file = archive.by_index(i).map_err(|e| {
            Error::Io(format!("Failed to read entry {}: {}", i, e))
        })?;
        let name = file.name().to_string();

        // Skip ComicInfo.xml during collection.
        if is_comicinfo_xml(&name) {
            continue;
        }

        let mut data = Vec::new();
        file.read_to_end(&mut data).map_err(|e| {
            Error::Io(format!("Failed to read entry {}: {}", name, e))
        })?;

        entries.push(ZipEntry::new(name, data));
    }

    Ok(entries)
}

/// Read all entries including ComicInfo.xml.
pub fn collect_zip_entries_all(path: &Path) -> Result<ZipEntries> {
    let file = std::fs::File::open(path).map_err(|e| {
        Error::Io(format!("Failed to open {}: {}", path.display(), e))
    })?;
    let mut archive = ZipArchive::new(file).map_err(|e| {
        Error::InvalidZip(format!("Not a valid ZIP: {}", e))
    })?;

    let mut entries: Vec<ZipEntry> = Vec::with_capacity(archive.len());
    for i in 0..archive.len() {
        let mut file = archive.by_index(i).map_err(|e| {
            Error::Io(format!("Failed to read entry {}: {}", i, e))
        })?;
        let name = file.name().to_string();

        let mut data = Vec::new();
        file.read_to_end(&mut data).map_err(|e| {
            Error::Io(format!("Failed to read entry {}: {}", name, e))
        })?;

        entries.push(ZipEntry::new(name, data));
    }

    Ok(entries)
}

// ---------------------------------------------------------------------------
// WriteZipFromEntries
// ---------------------------------------------------------------------------

/// Write a list of ZIP entries to disk, compressed with DEFLATE.
///
/// Creates a fresh ZIP archive with all entries at compression level 6
/// (ZIP_DEFAULT_COMPRESSION), in the order provided by the entries slice.
pub fn write_zip_from_entries(path: &Path, entries: &[ZipEntry]) -> Result<()> {
    let file = std::fs::File::create(path).map_err(|e| {
        Error::Io(format!("Failed to create {}: {}", path.display(), e))
    })?;
    let mut writer = ZipWriter::new(file);

    let options = FileOptions::default()
        .compression_method(CompressionMethod::Deflated);

    for entry in entries {
        writer.start_file(&entry.name, options).map_err(|e| {
            Error::Io(format!("Failed to add entry {}: {}", entry.name, e))
        })?;
        writer.write_all(&entry.data).map_err(|e| {
            Error::Io(format!("Failed to write data for {}: {}", entry.name, e))
        })?;
    }

    writer.finish().map_err(|e| {
        Error::Io(format!("Failed to finish ZIP: {}", e))
    })?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Image counting / validation helpers
// ---------------------------------------------------------------------------

/// Recognised image extensions (lowercase, without dot).
const IMAGE_EXTENSIONS: &[&str] = &[
    "jpg", "jpeg", "png", "webp", "bmp", "gif", "tiff", "tif",
];

/// Check whether an entry name has a recognised image extension.
pub fn is_image_entry(name: &str) -> bool {
    if let Some(ext) = Path::new(name).extension().and_then(|e| e.to_str()) {
        return IMAGE_EXTENSIONS.iter().any(|ie| ie.eq_ignore_ascii_case(ext));
    }
    false
}

/// Count image entries in a CBZ without reading full data.
pub fn count_image_entries(path: &Path) -> Result<usize> {
    let file = std::fs::File::open(path).map_err(|e| {
        Error::Io(format!("Failed to open {}: {}", path.display(), e))
    })?;
    let mut archive = ZipArchive::new(file).map_err(|e| {
        Error::InvalidZip(format!("Not a valid ZIP: {}", e))
    })?;

    let count: usize = (0..archive.len())
        .filter_map(|i| {
            archive.by_index(i).ok().map(|f| {
                is_image_entry(f.name()) as usize
            })
        })
        .sum();

    Ok(count)
}

/// Check if a CBZ is valid: readable ZIP with at least one image entry.
pub fn is_valid_cbz(path: &Path) -> Result<bool> {
    let count = count_image_entries(path)?;
    Ok(count > 0)
}

// ---------------------------------------------------------------------------
// Entry name management
// ---------------------------------------------------------------------------

/// Renames all entries in-place as page_NNNN.ext with computed padding.
/// Entries that aren't image files are left untouched.
pub fn renumber_entries(entries: &mut [ZipEntry], preserve_comicinfo: bool) {
    // Compute padding from total visible image count.
    let image_count = entries.iter().filter(|e| is_image_entry(&e.name)).count();
    let padding = page_padding_for(image_count);

    let mut img_idx = 0usize;
    for entry in entries.iter_mut() {
        if !is_image_entry(&entry.name) {
            continue;
        }
        img_idx += 1;
        if let Some(ext) = Path::new(&entry.name).extension().and_then(|e| e.to_str()) {
            entry.name = format_page_name(img_idx, padding, &format!(".{}", ext));
        } else {
            // Fallback: no extension — use .png.
            entry.name = format_page_name(img_idx, padding, ".png");
        }
    }

    if preserve_comicinfo {
        for entry in entries.iter_mut() {
            if entry.is_comicinfo() {
                entry.name = COMICINFO_XML.to_string();
            }
        }
    }
}

/// Remove all ComicInfo.xml entries from the list.
pub fn strip_comicinfo(entries: &mut Vec<ZipEntry>) -> usize {
    let before = entries.len();
    entries.retain(|e| !e.is_comicinfo());
    before - entries.len()
}

// ---------------------------------------------------------------------------
// Entry lookup
// ---------------------------------------------------------------------------

/// Returns a sorted list of entry names in the archive.
pub fn get_entry_names(path: &Path) -> Result<Vec<String>> {
    let file = std::fs::File::open(path).map_err(|e| {
        Error::Io(format!("Failed to open {}: {}", path.display(), e))
    })?;
    let mut archive = ZipArchive::new(file).map_err(|e| {
        Error::InvalidZip(format!("Not a valid ZIP: {}", e))
    })?;

    let names: Vec<String> = (0..archive.len())
        .filter_map(|i| archive.by_index(i).ok().map(|f| f.name().to_string()))
        .collect();

    Ok(names)
}

/// Read the full data of a single entry by name.
pub fn read_entry(path: &Path, entry_name: &str) -> Result<Vec<u8>> {
    let file = std::fs::File::open(path).map_err(|e| {
        Error::Io(format!("Failed to open {}: {}", path.display(), e))
    })?;
    let mut archive = ZipArchive::new(file).map_err(|e| {
        Error::InvalidZip(format!("Not a valid ZIP: {}", e))
    })?;

    for i in 0..archive.len() {
        if let Ok(mut file) = archive.by_index(i) {
            if file.name().eq_ignore_ascii_case(entry_name) {
                let mut data = Vec::new();
                file.read_to_end(&mut data).map_err(|e| {
                    Error::Io(format!("Failed to read entry {}: {}", entry_name, e))
                })?;
                return Ok(data);
            }
        }
    }

    Err(Error::EntryNotFound(entry_name.to_string()))
}

/// Get the first image entry name in a CBZ.
pub fn first_image_name(path: &Path) -> Result<Option<String>> {
    let file = std::fs::File::open(path).map_err(|e| {
        Error::Io(format!("Failed to open {}: {}", path.display(), e))
    })?;
    let mut archive = ZipArchive::new(file).map_err(|e| {
        Error::InvalidZip(format!("Not a valid ZIP: {}", e))
    })?;

    for i in 0..archive.len() {
        if let Ok(file) = archive.by_index(i) {
            if is_image_entry(file.name()) {
                return Ok(Some(file.name().to_string()));
            }
        }
    }

    Ok(None)
}

/// Get the first image entry name and its data.
pub fn first_image_data(path: &Path) -> Result<Option<Vec<u8>>> {
    let file = std::fs::File::open(path).map_err(|e| {
        Error::Io(format!("Failed to open {}: {}", path.display(), e))
    })?;
    let mut archive = ZipArchive::new(file).map_err(|e| {
        Error::InvalidZip(format!("Not a valid ZIP: {}", e))
    })?;

    for i in 0..archive.len() {
        if let Ok(mut file) = archive.by_index(i) {
            if is_image_entry(file.name()) {
                let mut data = Vec::new();
                file.read_to_end(&mut data).map_err(|e| {
                    Error::Io(format!("Failed to read first image: {}", e))
                })?;
                return Ok(Some(data));
            }
        }
    }

    Ok(None)
}

// ---------------------------------------------------------------------------
// Error types
// ---------------------------------------------------------------------------

/// Errors that can occur during ZIP operations.
#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("Invalid ZIP archive: {0}")]
    InvalidZip(String),

    #[error("Entry '{0}' not found in archive")]
    EntryNotFound(String),

    #[error("I/O error: {0}")]
    Io(String),
}

/// Result type for ZIP operations.
pub type Result<T> = std::result::Result<T, Error>;
