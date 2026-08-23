use std::path::Path;
use base64::{Engine as _, engine::general_purpose::STANDARD};

use crate::commands::batch_edit::BatchEditParams;

use rust_core::page_model::{PageModel, PageState as InternalPageState};
use rust_core::types::PageState as ApiPageState;

/// Convert API page states (base64 data) into the internal editing model.
fn to_internal(pages: &[ApiPageState]) -> Vec<InternalPageState> {
    pages
        .iter()
        .map(|p| InternalPageState {
            orig_name: p.orig_name.clone(),
            name: p.name.clone(),
            data: p.data.as_ref().map(|b64| STANDARD.decode(b64).unwrap_or_default()),
            deleted: p.gone,
        })
        .collect()
}

/// Convert the internal model back into API page states for the frontend.
fn to_api(model: &PageModel) -> Vec<ApiPageState> {
    model
        .pages()
        .iter()
        .enumerate()
        .map(|(i, p)| ApiPageState {
            name: p.name.clone(),
            orig_name: p.orig_name.clone(),
            gone: p.deleted,
            orig_index: i as i32,
            data: p.data.as_ref().map(|d| STANDARD.encode(d)),
        })
        .collect()
}

/// Shared helper that applies an in-place reorder/transform to a page model and
/// returns the resulting (base64-serialized) page list.
fn with_model(pages: Vec<ApiPageState>, f: impl FnOnce(&mut PageModel)) -> Vec<ApiPageState> {
    let internal = to_internal(&pages);
    let mut model = PageModel::from_pages(internal);
    f(&mut model);
    to_api(&model)
}

#[tauri::command]
pub async fn page_load(file_path: String) -> Result<Vec<rust_core::types::PageState>, String> {
    let entries = rust_core::zip_ops::collect_zip_entries(Path::new(&file_path))
        .map_err(|e| e.to_string())?;

    Ok(entries
        .into_iter()
        .enumerate()
        .map(|(i, entry)| rust_core::types::PageState {
            name: entry.name.clone(),
            orig_name: entry.name.clone(),
            gone: false,
            orig_index: i as i32,
            data: Some(STANDARD.encode(&entry.data)),
        })
        .collect())
}

// ---------------------------------------------------------------------------
// Reorder / transform commands (GAPS 2.1–2.7). These mirror the Pascal page
// context-menu actions and operate on an in-memory PageModel.
//
// Each command receives the current page list, applies the operation, and
// returns the reordered list so the frontend can re-render without a reload.
// ---------------------------------------------------------------------------

/// GAPS 2.1: move a page up one visible slot.
#[tauri::command]
pub async fn page_move_up(pages: Vec<ApiPageState>, index: usize) -> Vec<ApiPageState> {
    with_model(pages, |m| {
        m.move_up(index);
    })
}

/// GAPS 2.1: move a page down one visible slot.
#[tauri::command]
pub async fn page_move_down(pages: Vec<ApiPageState>, index: usize) -> Vec<ApiPageState> {
    with_model(pages, |m| {
        m.move_down(index);
    })
}

/// GAPS 2.2: move a page to the start of the list.
#[tauri::command]
pub async fn page_move_to_start(pages: Vec<ApiPageState>, index: usize) -> Vec<ApiPageState> {
    with_model(pages, |m| {
        m.move_to_start(index);
    })
}

/// GAPS 2.2: move a page to the end of the list.
#[tauri::command]
pub async fn page_move_to_end(pages: Vec<ApiPageState>, index: usize) -> Vec<ApiPageState> {
    with_model(pages, |m| {
        m.move_to_end(index);
    })
}

/// GAPS 2.3: sort pages ascending by name.
#[tauri::command]
pub async fn page_sort_asc(pages: Vec<ApiPageState>) -> Vec<ApiPageState> {
    with_model(pages, |m| {
        m.sort_asc();
    })
}

/// GAPS 2.3: sort pages descending by name.
#[tauri::command]
pub async fn page_sort_desc(pages: Vec<ApiPageState>) -> Vec<ApiPageState> {
    with_model(pages, |m| {
        m.sort_desc();
    })
}

/// GAPS 2.3: reverse the page order.
#[tauri::command]
pub async fn page_reverse(pages: Vec<ApiPageState>) -> Vec<ApiPageState> {
    with_model(pages, |m| {
        m.reverse();
    })
}

/// GAPS 2.4: renumber visible pages to sequential page_NNNN names.
#[tauri::command]
pub async fn page_renumber(pages: Vec<ApiPageState>) -> Vec<ApiPageState> {
    with_model(pages, |m| {
        m.renumber();
    })
}

/// GAPS 2.5: undo the last recorded change.
#[tauri::command]
pub async fn page_undo(pages: Vec<ApiPageState>) -> Vec<ApiPageState> {
    with_model(pages, |m| {
        m.undo();
    })
}

/// GAPS 2.6: insert new pages at the front (becomes page 0).
#[tauri::command]
pub async fn page_insert_front(
    pages: Vec<ApiPageState>,
    new_pages: Vec<ApiPageState>,
) -> Vec<ApiPageState> {
    with_model(pages, |m| {
        let internal = to_internal(&new_pages);
        let _ = m.insert_at(0, internal);
    })
}

/// GAPS 2.6: insert new pages at a given index.
#[tauri::command]
pub async fn page_insert_at(
    pages: Vec<ApiPageState>,
    index: usize,
    new_pages: Vec<ApiPageState>,
) -> Vec<ApiPageState> {
    with_model(pages, |m| {
        let internal = to_internal(&new_pages);
        let _ = m.insert_at(index, internal);
    })
}

/// GAPS 2.7: drag-drop reorder from one visible slot to another.
#[tauri::command]
pub async fn page_drag_drop(
    pages: Vec<ApiPageState>,
    from: usize,
    to: usize,
) -> Vec<ApiPageState> {
    with_model(pages, |m| {
        m.drag_drop(from, to);
    })
}

/// GAPS 2.8: single-page editor command. Applies an in-place resize / colour /
/// split edit to one page (by its global index into the working list) and returns
/// the updated list. Reuses the proven batch pipeline so output is byte-identical
/// and obeys Data-stream precedence: an already-edited page is edited on top of its
/// current bytes rather than the archive copy. Piece 0 replaces the source page and
/// extra split pieces insert after it; visible pages are renumbered to page_NNNN.ext.
#[tauri::command]
pub async fn page_edit_single(
    pages: Vec<ApiPageState>,
    index: usize,
    params: BatchEditParams,
) -> Vec<ApiPageState> {
    let resize_percent = if params.resize_percent > 0.0 {
        std::cmp::max(1, std::cmp::min(200, params.resize_percent as i32))
    } else {
        100
    };
    let do_resize = resize_percent != 100;
    let color_adjust = params.color_adjust.clone();
    let cut_lines = params.cut_lines.clone();
    let horizontal_lines = params.horizontal_lines;

    with_model(pages, |m| {
        if index >= m.pages().len() {
            return;
        }

        // Operate on the page's current Data (edited bytes win over the archive).
        let src = &m.pages()[index];
        let ext = src.name.rsplit('.').next().unwrap_or("png").to_string();
        let input = rust_core::batch_edit::MultiEditPageInput {
            idx: index,
            orig_name: String::new(),
            data: src.data.clone(),
            ext,
        };

        let multi = rust_core::batch_edit::MultiEditParams {
            resize: do_resize,
            percent: resize_percent,
            color_adj: rust_core::image_edit::ColorAdjust {
                grayscale: color_adjust.grayscale,
                sepia: color_adjust.sepia,
                invert: color_adjust.invert,
                r_gain: color_adjust.red_gain,
                g_gain: color_adjust.green_gain,
                b_gain: color_adjust.blue_gain,
                saturation: color_adjust.saturation,
                contrast: color_adjust.contrast,
                brightness: color_adjust.brightness,
                gamma: color_adjust.gamma,
            },
            split: !cut_lines.is_empty(),
            horizontal_lines,
            cut_lines,
        };

        let results = rust_core::batch_edit::apply_batch_to_inputs(&[input], &multi);
        rust_core::batch_edit::stage_results(m, &results);
    })
}

#[tauri::command]
pub async fn page_save(
    pages: Vec<rust_core::types::PageState>,
    file_path: String,
) -> Result<rust_core::types::SaveChangesResult, String> {
    // Convert frontend PageState → internal PageState (page_model module)
    let internal_pages: Vec<rust_core::page_model::PageState> = pages
        .iter()
        .map(|p| rust_core::page_model::PageState {
            orig_name: p.orig_name.clone(),
            name: p.name.clone(),
            data: p.data.as_ref().map(|b64| STANDARD.decode(b64).unwrap_or_default()),
            deleted: p.gone,
        })
        .collect();

    let model = rust_core::page_model::PageModel::from_pages(internal_pages);

    match rust_core::page_model::save_changes(&model, Path::new(&file_path)) {
        Ok(_) => Ok(rust_core::types::SaveChangesResult {
            success: true,
            error_msg: String::new(),
        }),
        Err(e) => Ok(rust_core::types::SaveChangesResult {
            success: false,
            error_msg: e,
        }),
    }
}
