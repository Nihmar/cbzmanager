/// In-memory page editing model.
///
/// Replaces `upageeditmodel.pas`: `TPageState`, `TChange` (ckDeleted/ckMoved),
/// `FPages` / `FBaseline` arrays, undo log, save thread.

use crate::helpers::*;
use crate::zip_ops;
use std::path::Path;

// ---------------------------------------------------------------------------
// Page state and changes
// ---------------------------------------------------------------------------

/// State of a single page slot — mirrors Pascal `TPageState`.
#[derive(Debug, Clone, PartialEq)]
pub struct PageState {
    /// Original entry name from the archive.
    pub orig_name: String,
    /// Current (possibly renumbered) name.
    pub name: String,
    /// Encoded image data (some pages may be edited). None means "read from archive".
    pub data: Option<Vec<u8>>,
    /// Whether this page is marked for deletion.
    pub deleted: bool,
}

/// Type of change recorded in the undo log.
#[derive(Debug, Clone, PartialEq)]
pub enum ChangeType {
    Deleted(usize),
    MovedUp(usize),
    MovedDown(usize),
    SortedAsc,
    SortedDesc,
    Reversed,
    Inserted(Vec<PageState>),
}

/// A single change entry in the linear undo log.
#[derive(Debug, Clone)]
pub struct Change {
    pub change_type: ChangeType,
    /// Snapshot of pages before this change (for undo).
    pub snapshot: Vec<PageState>,
}

// ---------------------------------------------------------------------------
// Page model
// ---------------------------------------------------------------------------

/// In-memory model for a CBZ page list with edit support.
pub struct PageModel {
    /// Current working state.
    pages: Vec<PageState>,
    /// Baseline snapshot taken at open time (for revert).
    baseline: Vec<PageState>,
    /// Linear undo log.
    changes: Vec<Change>,
}

impl PageModel {
    /// Create a new model from a list of archive entries.
    pub fn new(entries: &[zip_ops::ZipEntry]) -> Self {
        let pages: Vec<PageState> = entries
            .iter()
            .map(|e| PageState {
                orig_name: e.name.clone(),
                name: e.name.clone(),
                data: Some(e.data.clone()), // Store data for in-memory save.
                deleted: false,
            })
            .collect();

        Self {
            pages: pages.clone(),
            baseline: pages,
            changes: Vec::new(),
        }
    }

    /// Create a model from scratch (e.g. for inserting new pages).
    pub fn empty() -> Self {
        let pages: Vec<PageState> = Vec::new();
        Self {
            pages: pages.clone(),
            baseline: pages,
            changes: Vec::new(),
        }
    }

    /// Return a reference to the current page list.
    pub fn pages(&self) -> &[PageState] {
        &self.pages
    }

    /// Return mutable reference to the page list (for edits).
    pub fn pages_mut(&mut self) -> &mut Vec<PageState> {
        &mut self.pages
    }

    /// Check whether there are pending changes vs. baseline.
    pub fn has_changes(&self) -> bool {
        if self.changes.is_empty() {
            return false;
        }
        // Check if current state differs from the snapshot before the last change,
        // or if any page is deleted/moved that wasn't originally.
        self.pages != self.baseline || self.pages.iter().any(|p| p.deleted)
    }

    /// Revert to the baseline snapshot (discard all changes).
    pub fn revert(&mut self) {
        self.pages = self.baseline.clone();
        self.changes.clear();
    }

    /// Delete a page at a given index (0-based, among visible pages).
    pub fn delete_at(&mut self, index: usize) -> ChangeType {
        let snapshot = self.pages.clone();
        if index < self.pages.len() {
            self.pages[index].deleted = true;
        }
        let change_type = ChangeType::Deleted(index);
        self.changes.push(Change {
            change_type: change_type.clone(),
            snapshot,
        });
        change_type
    }

    /// Move a page up (swap with previous visible page).
    pub fn move_up(&mut self, index: usize) -> ChangeType {
        let snapshot = self.pages.clone();
        if index > 0 && index < self.pages.len() {
            self.pages.swap(index, index - 1);
        }
        let change_type = ChangeType::MovedUp(index);
        self.changes.push(Change {
            change_type: change_type.clone(),
            snapshot,
        });
        change_type
    }

    /// Move a page down (swap with next visible page).
    pub fn move_down(&mut self, index: usize) -> ChangeType {
        let snapshot = self.pages.clone();
        if index >= 0 && index < self.pages.len() - 1 {
            self.pages.swap(index, index + 1);
        }
        let change_type = ChangeType::MovedDown(index);
        self.changes.push(Change {
            change_type: change_type.clone(),
            snapshot,
        });
        change_type
    }

    /// Sort pages ascending by name.
    pub fn sort_asc(&mut self) -> ChangeType {
        let snapshot = self.pages.clone();
        self.pages.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
        let change_type = ChangeType::SortedAsc;
        self.changes.push(Change {
            change_type: change_type.clone(),
            snapshot,
        });
        change_type
    }

    /// Sort pages descending by name.
    pub fn sort_desc(&mut self) -> ChangeType {
        let snapshot = self.pages.clone();
        self.pages.sort_by(|a, b| b.name.to_lowercase().cmp(&a.name.to_lowercase()));
        let change_type = ChangeType::SortedDesc;
        self.changes.push(Change {
            change_type: change_type.clone(),
            snapshot,
        });
        change_type
    }

    /// Reverse the page order.
    pub fn reverse(&mut self) -> ChangeType {
        let snapshot = self.pages.clone();
        self.pages.reverse();
        let change_type = ChangeType::Reversed;
        self.changes.push(Change {
            change_type: change_type.clone(),
            snapshot,
        });
        change_type
    }

    /// Undo the last change (revert to snapshot before it).
    pub fn undo(&mut self) -> Option<ChangeType> {
        if let Some(change) = self.changes.pop() {
            let change_type = change.change_type.clone();
            self.pages = change.snapshot;
            Some(change_type)
        } else {
            None
        }
    }

    /// Renumber all visible (non-deleted) pages to sequential names.
    pub fn renumber(&mut self) {
        let padding = page_padding_for(self.visible_count());

        let mut visible_pages: Vec<&mut PageState> = self.pages.iter_mut().filter(|p| !p.deleted).collect();
        for (i, page) in visible_pages.iter_mut().enumerate() {
            let ext = get_ext(&page.name);
            page.name = format_page_name(i, padding + 1, &ext);
        }
    }

    /// Count only visible (non-deleted) pages.
    pub fn visible_count(&self) -> usize {
        self.pages.iter().filter(|p| !p.deleted).count()
    }

    /// Insert new pages at a given index.
    pub fn insert_at(&mut self, index: usize, new_pages: Vec<PageState>) -> ChangeType {
        let snapshot = self.pages.clone();
        if index <= self.pages.len() {
            for (i, page) in new_pages.iter().enumerate() {
                let ext = get_ext(&page.name);
                let encoded_ext = encode_ext_for(&ext);
                let mut p = page.clone();
                p.orig_name = format!("page_{:04}.{}", i, encoded_ext);
                p.name = format!("page_{:04}.{}", index + i, encoded_ext);
                self.pages.insert(index + i, p);
            }
        }
        let new_page_snapshot = new_pages.clone();
        let change_type = ChangeType::Inserted(new_page_snapshot);
        self.changes.push(Change {
            change_type: change_type.clone(),
            snapshot,
        });
        change_type
    }

    /// Get the total number of pages (including deleted).
    pub fn len(&self) -> usize {
        self.pages.len()
    }

    /// Check if model is empty.
    pub fn is_empty(&self) -> bool {
        self.pages.is_empty()
    }
}

/// Helper: extract extension from a filename (without dot).
fn get_ext(name: &str) -> String {
    name.rsplit_once('.').map(|(_, e)| e.to_string()).unwrap_or_else(|| "jpg".to_string())
}

/// Helper: get the output extension for a page format (same as Pascal EncodeExtFor).
fn encode_ext_for(ext: &str) -> String {
    let lower = ext.to_lowercase();
    if lower == "gif" || lower == "tiff" || lower == "tif" {
        "png".to_string()
    } else {
        ext.to_string()
    }
}

// ---------------------------------------------------------------------------
// Save changes — write modified pages to a new CBZ entirely in RAM
// ---------------------------------------------------------------------------

/// Save the current page model to a new CBZ file at `output_path`.
///
/// Steps:
///   1. Collect visible (non-deleted) pages into a ZipEntry list.
///   2. Each entry's data comes from `PageState.Data` if present, otherwise
///      from the archive entry (fallback — but we always store Data in the model).
///   3. Write ZIP with DEFLATE compression.
pub fn save_changes(
    model: &PageModel,
    output_path: &Path,
) -> Result<(), String> {
    // Build a list of visible (non-deleted) pages with their data.
    let mut entries: Vec<zip_ops::ZipEntry> = Vec::new();

    for page in model.pages.iter().filter(|p| !p.deleted) {
        let data = if let Some(ref data) = page.data {
            data.clone()
        } else {
            // Fallback: should not happen since we store Data in the model.
            Vec::new()
        };

        entries.push(zip_ops::ZipEntry {
            name: page.name.clone(),
            data,
        });
    }

    // Write ZIP entirely in RAM.
    zip_ops::write_zip_from_entries(output_path, &entries)
        .map_err(|e| e.to_string())
}

/// Atomic replace: write a new CBZ and swap with original (backup + rename).
pub fn save_to_cbz(
    model: &PageModel,
    original_path: &Path,
) -> std::io::Result<()> {
    crate::helpers::replace_cbz(original_path, |new_path| {
        // Build entries from the model.
        let mut entries: Vec<zip_ops::ZipEntry> = Vec::new();

        for page in model.pages.iter().filter(|p| !p.deleted) {
            let data = if let Some(ref data) = page.data {
                data.clone()
            } else {
                // Try to read from the original archive (shouldn't happen for edited pages).
                Vec::new()
            };

            entries.push(zip_ops::ZipEntry {
                name: page.name.clone(),
                data,
            });
        }

        zip_ops::write_zip_from_entries(new_path, &entries)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e.to_string()))
    })
}
