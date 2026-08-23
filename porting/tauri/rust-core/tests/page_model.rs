mod common;

use rust_core::page_model::{ChangeType, PageModel, PageState};
use rust_core::zip_ops::ZipEntry;

fn entry(name: &str, data: Vec<u8>) -> ZipEntry {
    ZipEntry::new(name, data)
}

/// Unique scratch dir per test so parallel tests don't clobber each other's output.
fn workdir() -> std::path::PathBuf {
    use std::time::{SystemTime, UNIX_EPOCH};
    let mut d = std::env::temp_dir();
    d.push(format!(
        "cbztest_pm_{}_{}",
        std::process::id(),
        SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos()
    ));
    std::fs::create_dir_all(&d).unwrap();
    d
}

/// Build a model whose three visible pages are named by their `names`.
fn model_from(names: &[&str]) -> PageModel {
    let entries = names
        .iter()
        .map(|n| entry(*n, format!("{n:?}").into_bytes()))
        .collect::<Vec<_>>();
    PageModel::new(&entries)
}

#[test]
fn delete_marks_and_save_drops_the_page() {
    let mut m = model_from(&["a.png", "b.png", "c.png"]);
    let ch = m.delete_at(1);
    assert_eq!(ch, ChangeType::Deleted(1));

    assert!(m.has_changes());
    // Deleted page is a Gone slot but still occupies its array index.
    assert!(m.pages()[1].deleted);
    assert_eq!(m.visible_count(), 2);

    // Save must exclude the deleted page entirely.
    let dir = workdir();
    std::fs::create_dir_all(&dir).unwrap();
    rust_core::page_model::save_changes(&m, &dir.join("out.cbz")).unwrap();
    let names = rust_core::zip_ops::get_entry_names(&dir.join("out.cbz")).unwrap();
    assert_eq!(names, vec!["a.png".to_string(), "c.png".to_string()]);
}

#[test]
fn move_up_and_down_swap_visible_neighbours() {
    let mut m = model_from(&["a.png", "b.png", "c.png"]);
    m.move_up(1); // b -> a,b,c  => b,a,c
    assert_eq!(m.pages().iter().map(|p| p.name.as_str()).collect::<Vec<_>>(), vec!["b.png","a.png","c.png"]);
    m.move_down(0); // a back to the middle
    assert_eq!(m.pages()[1].name, "b.png");
}

#[test]
fn sort_asc_and_desc_and_reverse() {
    let mut m = model_from(&["c.png", "a.png", "b.png"]);
    m.sort_asc();
    assert_eq!(
        m.pages().iter().map(|p| p.name.as_str()).collect::<Vec<_>>(),
        vec!["a.png", "b.png", "c.png"]
    );
    m.reverse();
    assert_eq!(
        m.pages()[0].name, "c.png"
    );
    let mut d = model_from(&["c.png", "a.png", "b.png"]);
    d.sort_desc();
    assert_eq!(d.pages()[0].name, "c.png");
}

#[test]
fn undo_reverts_to_snapshot() {
    let mut m = model_from(&["a.png", "b.png", "c.png"]);
    m.move_up(1);
    let undone = m.undo();
    assert!(undone.is_some());
    // Reverted to original order.
    assert_eq!(m.pages()[0].name, "a.png");
    assert!(!m.has_changes(), "undo clears the change flag");
    assert!(m.undo().is_none(), "no more changes to undo");
}

#[test]
fn revert_discards_everything() {
    let mut m = model_from(&["a.png", "b.png", "c.png"]);
    m.delete_at(0);
    m.move_down(0);
    m.revert();
    assert_eq!(m.pages().len(), 3);
    assert!(!m.has_changes());
    assert!(!m.pages()[0].deleted);
}

#[test]
fn insert_at_places_page_in_sequence() {
    let mut m = model_from(&["a.png", "b.png", "c.png"]);
    let new_pages = vec![PageState {
        orig_name: "new".into(),
        name: "new".into(),
        data: None,
        deleted: false,
    }];
    m.insert_at(1, new_pages);

    // Originals keep their names; the inserted page sits at index 1 and the
    // remaining originals shift right.
    assert_eq!(m.pages()[0].orig_name, "a.png");
    assert_eq!(m.pages()[2].orig_name, "b.png");
    assert_eq!(m.pages()[3].orig_name, "c.png");
    assert_eq!(m.pages().len(), 4);
}

#[test]
fn renumber_names_pages_sequentially() {
    let mut m = model_from(&["x.png", "y.png", "z.png"]);
    m.delete_at(0); // remove x; visible = [y, z]
    m.renumber();
    let names: Vec<String> = m.pages().iter().filter(|p| !p.deleted).map(|p| p.name.clone()).collect();
    // Reference semantics: pages are renumbered 1-based (page_0001, page_0002...) with a dot on the extension.
    assert_eq!(names[0], "page_0001.png");
    assert_eq!(names[1], "page_0002.png");
}

// Regression for bughunt T2: the editor's renumber used page_padding_for(count)
// + 1 — one digit wider than every other path (and than Pascal PageRenumber,
// which uses the fixed PAGE_PAD_DEFAULT = 4). Lock the fixed width here.
#[test]
fn renumber_uses_fixed_editor_padding() {
    let mut m = model_from(&[
        "p1.png", "p2.png", "p3.png", "p4.png", "p5.png",
        "p6.png", "p7.png", "p8.png", "p9.png",
    ]);
    m.renumber();
    let names: Vec<String> = m.pages().iter().filter(|p| !p.deleted).map(|p| p.name.clone()).collect();
    assert_eq!(names[8], "page_0009.png", "9 pages still pad to the fixed editor width");
}

#[test]
fn save_edited_data_wins_over_archive() {
    let mut m = PageModel::from_pages(vec![
        PageState { orig_name: "page_0001.png".into(), name: "page_0001.png".into(), data: Some(b"ORIGINAL".to_vec()), deleted: false },
        PageState { orig_name: "page_0002.png".into(), name: "page_0002.png".into(), data: Some(b"ORIGINAL2".to_vec()), deleted: false },
    ]);
    // Simulate the page editor replacing page 1's content.
    m.pages_mut()[0].data = Some(b"EDITED-BYTES".to_vec());

    let dir = workdir();
    std::fs::create_dir_all(&dir).unwrap();
    rust_core::page_model::save_changes(&m, &dir.join("out.cbz")).unwrap();
    let data = rust_core::zip_ops::read_entry(&dir.join("out.cbz"), "page_0001.png").unwrap();
    assert_eq!(data, b"EDITED-BYTES".to_vec(), "staged Data must win over the archive copy");
}

#[test]
fn move_to_start_and_end_reorder_visible_pages() {
    let mut m = model_from(&["a.png", "b.png", "c.png"]);
    m.move_to_start(2); // c -> front
    assert_eq!(
        m.pages().iter().map(|p| p.name.as_str()).collect::<Vec<_>>(),
        vec!["c.png", "a.png", "b.png"]
    );
    m.move_to_end(0); // c -> back
    assert_eq!(
        m.pages().iter().map(|p| p.name.as_str()).collect::<Vec<_>>(),
        vec!["a.png", "b.png", "c.png"]
    );
}

#[test]
fn move_to_start_skips_leading_deleted_slots() {
    let mut m = model_from(&["a.png", "b.png", "c.png"]);
    m.delete_at(0); // [GONE a, b, c]
    m.move_to_start(2); // c to the front of the visible order
    // The deleted placeholder (a) stays as a skipped slot; the visible order is c,b.
    let visible: Vec<&str> = m
        .pages()
        .iter()
        .filter(|p| !p.deleted)
        .map(|p| p.name.as_str())
        .collect();
    assert_eq!(visible, vec!["c.png", "b.png"]);
}

#[test]
fn drag_drop_moves_between_visible_slots() {
    let mut m = model_from(&["a.png", "b.png", "c.png", "d.png"]);
    let ch = m.drag_drop(0, 3); // a -> after d
    assert_eq!(ch, ChangeType::Dragged(0));
    assert_eq!(
        m.pages().iter().map(|p| p.name.as_str()).collect::<Vec<_>>(),
        vec!["b.png", "c.png", "d.png", "a.png"]
    );
}

#[test]
fn drag_drop_snap_past_deleted_slots() {
    let mut m = model_from(&["a.png", "b.png", "c.png"]);
    m.delete_at(1); // [a, GONE b, c]
    m.drag_drop(2, 1); // move c to slot 1, which snaps past the deleted b
    // Visible order is a,c (the placeholder for b remains skipped).
    let visible: Vec<&str> = m
        .pages()
        .iter()
        .filter(|p| !p.deleted)
        .map(|p| p.name.as_str())
        .collect();
    assert_eq!(visible, vec!["a.png", "c.png"]);
}

#[test]
fn undo_reverts_drag_drop() {
    let mut m = model_from(&["a.png", "b.png", "c.png"]);
    m.drag_drop(0, 2);
    let undone = m.undo();
    assert!(undone.is_some());
    assert_eq!(m.pages()[0].name, "a.png");
    assert_eq!(m.pages()[2].name, "c.png");
}

#[test]
fn save_empty_model_writes_valid_empty_cbz() {
    let m = model_from(&[]);
    assert!(!m.has_changes());
    let dir = workdir();
    std::fs::create_dir_all(&dir).unwrap();
    let out = dir.join("out.cbz");
    rust_core::page_model::save_changes(&m, &out).unwrap();
    assert!(out.exists());
    assert_eq!(rust_core::zip_ops::get_entry_names(&out).unwrap().len(), 0);
}
