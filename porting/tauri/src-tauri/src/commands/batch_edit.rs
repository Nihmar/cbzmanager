use std::path::Path;
use tauri::Emitter;
use base64::{Engine as _, engine::general_purpose::STANDARD};

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BatchEditParams {
    /// Percentage resize (1-200), 0 means no resize.
    pub resize_percent: f64,
    /// Colour adjustment parameters.
    pub color_adjust: ColorAdjustParams,
    /// Uniform split lines (normalised 0-1 positions, sorted ascending),
    /// applied to every page — same semantics as Lazarus ubatchedit.
    pub cut_lines: Vec<f64>,
    /// True = horizontal cut lines (top/bottom), false = vertical.
    #[serde(default = "default_true")]
    pub horizontal_lines: bool,
}

fn default_true() -> bool {
    true
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ColorAdjustParams {
    pub grayscale: bool,
    pub sepia: bool,
    pub invert: bool,
    pub red_gain: f64,
    pub green_gain: f64,
    pub blue_gain: f64,
    pub saturation: f64,
    pub contrast: f64,
    pub brightness: f64,
    pub gamma: f64,
}

impl Default for ColorAdjustParams {
    fn default() -> Self {
        Self {
            grayscale: false,
            sepia: false,
            invert: false,
            red_gain: 1.0,
            green_gain: 1.0,
            blue_gain: 1.0,
            saturation: 1.0,
            contrast: 1.0,
            brightness: 1.0,
            gamma: 1.0,
        }
    }
}

/// Apply batch edit to all pages of a CBZ file.
/// Returns the edited pages with updated data and names.
#[tauri::command]
pub async fn apply_batch_edit(
    app: tauri::AppHandle,
    file_path: String,
    params: BatchEditParams,
) -> Result<Vec<rust_core::types::PageState>, String> {
    let entries = rust_core::zip_ops::collect_zip_entries(Path::new(&file_path))
        .map_err(|e| format!("Cannot read archive: {}", e))?;

    if entries.is_empty() {
        return Ok(Vec::new());
    }

    // Build MultiEditParams from frontend params
    let resize_percent = if params.resize_percent > 0.0 {
        std::cmp::max(1, std::cmp::min(200, params.resize_percent as i32))
    } else {
        100
    };
    let do_resize = resize_percent != 100;

    let color_adj = rust_core::image_edit::ColorAdjust {
        grayscale: params.color_adjust.grayscale,
        sepia: params.color_adjust.sepia,
        invert: params.color_adjust.invert,
        r_gain: params.color_adjust.red_gain,
        g_gain: params.color_adjust.green_gain,
        b_gain: params.color_adjust.blue_gain,
        saturation: params.color_adjust.saturation,
        contrast: params.color_adjust.contrast,
        brightness: params.color_adjust.brightness,
        gamma: params.color_adjust.gamma,
    };

    let multi_edit_params = rust_core::batch_edit::MultiEditParams {
        resize: do_resize,
        percent: resize_percent,
        color_adj,
        split: !params.cut_lines.is_empty(),
        horizontal_lines: params.horizontal_lines,
        cut_lines: params.cut_lines.clone(),
    };

    // Build the per-page inputs from archive entries. Order is significant: each
    // input's idx identifies its source page and pins where its results stage.
    let inputs: Vec<rust_core::batch_edit::MultiEditPageInput> = entries
        .iter()
        .enumerate()
        .map(|(idx, entry)| rust_core::batch_edit::MultiEditPageInput {
            idx,
            orig_name: entry.name.clone(),
            data: Some(entry.data.clone()),
            ext: entry.name.rsplit('.').next().unwrap_or("png").to_string(),
        })
        .collect();

    // Parallel decode -> resize/colour/split -> encode. Byte-identical output for
    // any thread count; undecodable/failed pages come back with no pieces.
    let results = rust_core::batch_edit::apply_batch_to_inputs(&inputs, &multi_edit_params);

    let mut out: Vec<rust_core::types::PageState> = Vec::new();
    for result in &results {
        // Re-read the original entry by its pinned index.
        let entry = &entries[result.idx];

        if result.pieces.is_empty() {
            // Undecodable or failed to apply: keep the original page verbatim.
            out.push(rust_core::types::PageState {
                name: entry.name.clone(),
                orig_name: entry.name.clone(),
                gone: false,
                orig_index: result.idx as i32,
                data: Some(STANDARD.encode(&entry.data)),
            });
        } else {
            // Piece 0 replaces the page; extra split pieces insert after it.
            for piece in &result.pieces {
                out.push(rust_core::types::PageState {
                    name: format!("page_{}.{}", result.idx + 1, piece.ext),
                    orig_name: entry.name.clone(),
                    gone: false,
                    orig_index: result.idx as i32,
                    data: Some(STANDARD.encode(&piece.data)),
                });
            }
        }
    }

    // Emit completion
    let _ = app.emit(
        "progress",
        crate::commands::ProgressEvent {
            percent: 100,
            message: "Batch edit complete".to_string(),
            phase: "batch_edit".to_string(),
        },
    );

    Ok(out)
}
