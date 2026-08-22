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

    let mut results = Vec::new();
    for (idx, entry) in entries.iter().enumerate() {
        // Check progress
        let total = entries.len();
        if total > 0 && idx % 5 == 0 {
            let pct = (idx as i32 * 95) / total as i32;
            let _ = app.emit(
                "progress",
                crate::commands::ProgressEvent {
                    percent: pct as u8,
                    message: format!("Applying batch edit..."),
                    phase: "batch_edit".to_string(),
                },
            );
        }

        // Decode image
        let img = match rust_core::batch_edit::decode_page_input(
            &rust_core::batch_edit::MultiEditPageInput {
                idx: idx,
                orig_name: entry.name.clone(),
                data: Some(entry.data.clone()),
                ext: entry.name.rsplit('.').next().unwrap_or("png").to_string(),
            },
        ) {
            Some(img) => img,
            None => {
                // Failed to decode — keep original page state
                results.push(rust_core::types::PageState {
                    name: entry.name.clone(),
                    orig_name: entry.name.clone(),
                    gone: false,
                    orig_index: idx as i32,
                    data: Some(STANDARD.encode(&entry.data)),
                });
                continue;
            }
        };

        // Apply edit pipeline
        let (pieces, success) = rust_core::batch_edit::apply_edit_to_image(
            &img,
            &multi_edit_params,
            entry.name.rsplit('.').next().unwrap_or("png"),
        );

        if !success || pieces.is_empty() {
            // Failed to apply edits — keep original page state
            results.push(rust_core::types::PageState {
                name: entry.name.clone(),
                orig_name: entry.name.clone(),
                gone: false,
                orig_index: idx as i32,
                data: Some(STANDARD.encode(&entry.data)),
            });
            continue;
        }

        // Encode pieces and stage into results
        for piece in &pieces {
            results.push(rust_core::types::PageState {
                name: format!("page_{}.{}", idx + 1, piece.ext),
                orig_name: entry.name.clone(),
                gone: false,
                orig_index: idx as i32,
                data: Some(STANDARD.encode(&piece.data)),
            });
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

    Ok(results)
}
