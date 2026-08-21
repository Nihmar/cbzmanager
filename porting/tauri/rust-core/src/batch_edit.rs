/// Batch page-edit pipeline — applies uniform edits (resize, colour adjust, split) to pages.
///
/// Replaces `ubatchedit.pas`: `TMultiEditParams`, `ApplyMultiEditToImage`
/// (decode → resize → colours → split → encode pieces), and the background worker.
/// Pure pipeline, no GUI: decodes current page state, applies edits, encodes output.

use image::DynamicImage;

use crate::image_edit;
use crate::image_util;
use crate::page_model::{ChangeType, PageModel, PageState};
use crate::types::*;

// ---------------------------------------------------------------------------
// Batch edit parameters
// ---------------------------------------------------------------------------

/// Uniform edit parameters for a batch run — mirrors Pascal `TMultiEditParams`.
#[derive(Debug, Clone)]
pub struct MultiEditParams {
    /// Apply percent resize.
    pub resize: bool,
    /// Resize percentage (50..200, 100 = unchanged).
    pub percent: i32,
    /// Color adjustment pipeline.
    pub color_adj: image_edit::ColorAdjust,
    /// Apply split with cut lines.
    pub split: bool,
    /// Cut line orientation.
    pub horizontal_lines: bool,
    /// Normalized 0..1 positions, sorted ascending.
    pub cut_lines: Vec<f64>,
}

impl Default for MultiEditParams {
    fn default() -> Self {
        Self::neutral()
    }
}

impl MultiEditParams {
    /// Create neutral (no-change) parameters.
    pub fn neutral() -> Self {
        Self {
            resize: false,
            percent: 100,
            color_adj: image_edit::ColorAdjust::identity(),
            split: false,
            horizontal_lines: true,
            cut_lines: Vec::new(),
        }
    }

    /// Check if these parameters produce no changes.
    pub fn is_neutral(&self) -> bool {
        (!self.resize || self.percent == 100)
            && !self.split
            && self.color_adj.is_neutral()
    }
}

/// Result for one encoded piece of a page.
#[derive(Debug)]
pub struct MultiEditPiece {
    /// Encoded bytes (JPEG q92, WebP q75, PNG/BMP lossless).
    pub data: Vec<u8>,
    /// Output extension.
    pub ext: String,
}

/// Result for one source page: 1 piece (no split) or N+1 pieces (split).
#[derive(Debug)]
pub struct MultiEditPageResult {
    /// Model index of the source page.
    pub idx: usize,
    /// Encoded pieces in reading order.
    pub pieces: Vec<MultiEditPiece>,
}

/// Input descriptor for one page.
#[derive(Debug)]
pub struct MultiEditPageInput {
    /// Model index.
    pub idx: usize,
    /// Archive entry name (empty if data is provided directly).
    pub orig_name: String,
    /// Current edited bytes (if the page was already modified).
    pub data: Option<Vec<u8>>,
    /// Current extension.
    pub ext: String,
}

// ---------------------------------------------------------------------------
// Pipeline
// ---------------------------------------------------------------------------

/// Apply the full batch-edit pipeline to one decoded image.
///
/// Steps: resize → color adjust → split → encode pieces.
/// Returns (pieces, success). On failure, returns empty pieces.
pub fn apply_edit_to_image(
    img: &DynamicImage,
    params: &MultiEditParams,
    orig_ext: &str,
) -> (Vec<MultiEditPiece>, bool) {
    use image::DynamicImage;

    if img.width() == 0 || img.height() == 0 {
        return (Vec::new(), false);
    }

    let mut cur = img.clone();

    // Step 1: Resize.
    if params.resize && params.percent != 100 {
        let new_w = ((cur.width() as f64 * params.percent as f64 / 100.0).max(1.0)) as u32;
        let new_h = ((cur.height() as f64 * params.percent as f64 / 100.0).max(1.0)) as u32;
        match image_edit::resample_image(&cur, new_w, new_h) {
            Some(resized) => cur = resized,
            None => return (Vec::new(), false),
        }
    }

    // Step 2: Color adjust.
    if !params.color_adj.is_neutral() {
        match image_edit::adjust_colors(&cur, &params.color_adj) {
            Some(adjusted) => cur = adjusted,
            None => return (Vec::new(), false),
        }
    }

    // Step 3: Split or single encode.
    if params.split && !params.cut_lines.is_empty() {
        let cut_defs: Vec<image_edit::CutLine> = params.cut_lines.iter().map(|&pos| {
            image_edit::CutLine {
                position: pos,
                horizontal: params.horizontal_lines,
            }
        }).collect();

        match image_edit::split_image(&cur, &cut_defs) {
            Some(pieces) => {
                let output_ext = encode_ext_for(orig_ext);
                let mut result_pieces: Vec<MultiEditPiece> = Vec::new();
                for piece in pieces {
                    match encode_piece(&piece, &output_ext) {
                        Some(encoded) => {
                            result_pieces.push(MultiEditPiece {
                                data: encoded,
                                ext: output_ext.clone(),
                            });
                        }
                        None => return (Vec::new(), false), // Fail on any piece failure.
                    }
                }
                (result_pieces, true)
            }
            None => (Vec::new(), false),
        }
    } else {
        // No split: single piece.
        let output_ext = encode_ext_for(orig_ext);
        match encode_piece(&cur, &output_ext) {
            Some(data) => {
                (vec![MultiEditPiece { data, ext: output_ext }], true)
            }
            None => (Vec::new(), false),
        }
    }
}

/// Get the output extension for a page format (same as Pascal EncodeExtFor).
fn encode_ext_for(ext: &str) -> String {
    let lower = ext.to_lowercase();
    if lower == "gif" || lower == "tiff" || lower == "tif" {
        "png".to_string()
    } else {
        ext.to_string()
    }
}

/// Encode a piece to the target format.
fn encode_piece(piece: &DynamicImage, ext: &str) -> Option<Vec<u8>> {
    use image::DynamicImage;
    match ext.to_lowercase().as_str() {
        "jpg" | "jpeg" => Some(image_util::encode_jpeg(piece).ok()?),
        "webp" => Some(image_util::encode_webp_default(piece).ok()?),
        "png" | "bmp" => Some(image_util::encode_png(piece).ok()?),
        _ => Some(image_util::encode_png(piece).ok()?), // Default to lossless.
    }
}

/// Decode a page's current state (Data stream if present, else from archive entry).
pub fn decode_page_input(input: &MultiEditPageInput) -> Option<DynamicImage> {
    use image::DynamicImage;
    if let Some(ref data) = input.data {
        // Try to decode from Data stream.
        image_util::decode_image(data).ok()
    } else if !input.orig_name.is_empty() {
        // Decode from archive entry (not yet implemented — returns None for now).
        // This would require access to the CBZ file path, which is handled in main.pas.
        None
    } else {
        None
    }
}

/// Stage batch-edit results into the page model.
///
/// Piece 0 replaces the source page (ckEdited), extra split pieces are inserted
/// after it (ckInserted). Iterates in descending index order so insertions
/// don't shift pending indices.
pub fn stage_results(
    model: &mut PageModel,
    results: &[MultiEditPageResult],
) -> Vec<ChangeType> {
    let mut changes: Vec<ChangeType> = Vec::new();

    // Process in descending order to avoid index shifting.
    let mut sorted_results: Vec<&MultiEditPageResult> = results.iter().collect();
    sorted_results.sort_by(|a, b| b.idx.cmp(&a.idx));

    for result in sorted_results {
        if result.pieces.is_empty() {
            continue; // Undecodable page — skip.
        }

        let had_split = result.pieces.len() > 1;

        // Get the page index.
        let pages = model.pages_mut();
        if result.idx >= pages.len() {
            continue;
        }

        // Replace piece 0 into the source page.
        let piece0 = &result.pieces[0];
        pages[result.idx].data = Some(piece0.data.clone());
        pages[result.idx].name = format!("page_{:04}.{}", result.idx + 1, piece0.ext);

        changes.push(ChangeType::Edited);

        // Insert extra split pieces after the source.
        if had_split {
            let mut new_pages: Vec<PageState> = Vec::new();
            for (i, piece) in result.pieces.iter().skip(1).enumerate() {
                new_pages.push(PageState {
                    orig_name: String::new(), // OrigName empty — can't match archive entry.
                    name: format!("page_{:04}.{}", model.pages().len() + i, piece.ext),
                    data: Some(piece.data.clone()),
                    deleted: false,
                });
            }

            let change_type = model.insert_at(result.idx + 1, new_pages);
            changes.push(change_type);
        }
    }

    // Renumber all visible pages.
    model.renumber();

    changes
}
