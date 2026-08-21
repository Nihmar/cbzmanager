//! Merge service integration tests — classification, CPV batching and the
//! documented "not-enough-chapters → no volume" divergence (matches the Python
//! reference: `num_volumes = int(num_chapters / chapters_per_volume)`, skipped
//! when zero).

mod common;

use std::path::{Path, PathBuf};

use common::*;

fn tempdir(tag: &str) -> PathBuf {
    let mut d = std::env::temp_dir();
    d.push(format!(
        "cbzmerge_{}_{}_{:?}",
        tag,
        std::process::id(),
        std::thread::current().id()
    ));
    std::fs::create_dir_all(&d).unwrap();
    d
}

/// Write `n_pages` page PNGs into a chapter file named `"series - {num:04}.cbz"`.
fn make_chapter(dir: &Path, series: &str, num: i32, n_pages: usize) -> PathBuf {
    use rust_core::zip_ops::{write_zip_from_entries, ZipEntry};
    let path = dir.join(format!("{} - {:04}.cbz", series, num));
    let pages: Vec<ZipEntry> = (1..=n_pages as u32)
        .map(|p| {
            ZipEntry::new(
                format!("page_{:04}.png", p),
                make_png(8, 8, ((num as u32) * 100 + p) as u8),
            )
        })
        .collect();
    write_zip_from_entries(&path, &pages).expect("write chapter");
    path
}

fn volume_files(dir: &Path, series: &str) -> Vec<PathBuf> {
    std::fs::read_dir(dir)
        .ok()
        .map(|rd| {
            rd.filter_map(|e| e.ok())
                .map(|e| e.path())
                .filter(|p| {
                    p.file_name()
                        .and_then(|s| s.to_str())
                        .map(|n| n.starts_with(&format!("{} V", series)))
                        .unwrap_or(false)
                })
                .collect()
        })
        .unwrap_or_default()
}

#[test]
fn classify_chapters_by_series_and_number() {
    let dir = tempdir("classify");
    make_chapter(&dir, "Alpha", 3, 1);
    make_chapter(&dir, "Alpha", 1, 1);
    make_chapter(&dir, "Alpha", 2, 1);
    make_chapter(&dir, "Beta", 1, 1);

    let (chapters, volumes) = rust_core::merge::parse_cbz_files(&dir);

    assert_eq!(volumes.len(), 0, "no volume files present");
    assert_eq!(chapters.len(), 4, "all chapters classified");

    // Sorted by series then chapter number.
    assert_eq!(chapters[0].series, "Alpha");
    assert_eq!(chapters[0].chapter_num, 1);
    assert_eq!(chapters[2].chapter_num, 3);
    assert_eq!(chapters[3].series, "Beta");
}

#[test]
fn classify_is_case_insensitive_extension() {
    let dir = tempdir("classify_upper");
    use rust_core::zip_ops::ZipEntry;
    rust_core::zip_ops::write_zip_from_entries(
        &dir.join("Gamma - 0001.CBZ"),
        &[ZipEntry::new("page_0001.png", make_png(4, 4, 1))],
    )
    .unwrap();

    let (chapters, _) = rust_core::merge::parse_cbz_files(&dir);
    assert_eq!(chapters.len(), 1, ".CBZ is matched case-insensitively");
}

#[test]
fn default_cpv_creates_single_volume_and_renumbers_pages() {
    let dir = tempdir("default7");
    // 7 chapters of 3 pages each. Default CPV is 7 → one full volume, no leftover.
    for n in 1..=7u32 {
        make_chapter(&dir, "Saga", n as i32, 3);
    }

    let results = rust_core::merge::merge_chapters(&dir, false, false, None, None);
    assert_eq!(results.len(), 1);
    let series = &results[0];
    assert_eq!(series.series_name, "Saga");
    assert_eq!(series.volumes_created, 1);
    assert_eq!(series.error_msg, "");
    assert_eq!(series.total_pages, 21, "7 chapters * 3 pages");

    // Exactly one volume file, sequentially renumbered pages, comicinfo absent.
    let vols = volume_files(&dir, "Saga");
    assert_eq!(vols.len(), 1);
    let names: Vec<String> = cbz_names(&vols[0]);
    assert_eq!(names.len(), 21);
    // padding = max(3, len(str(total_images))) — exactly what the Python
    // reference (merge.py:104) and its own test (test_merge.py:61) use.
    assert_eq!(names[0], "page_001.png");
    assert_eq!(names[20], "page_021.png");
}

#[test]
fn not_enough_chapters_creates_no_volume() {
    // 4 chapters < default CPV 7 → the series is skipped entirely (Python
    // reference: `if num_chapters < chapters_per_volume: skip`).
    let dir = tempdir("tooshort");
    for n in 1..=5u32 {
        make_chapter(&dir, "Mini", n as i32, 2);
    }

    let results = rust_core::merge::merge_chapters(&dir, false, false, None, None);
    assert!(results.is_empty(), "skipped series yields no plan");
    assert_eq!(volume_files(&dir, "Mini").len(), 0, "no volume file written");
}

#[test]
fn deletion_removes_source_chapters_after_merge() {
    let dir = tempdir("delete");
    for n in 1..=7u32 {
        make_chapter(&dir, "Del", n as i32, 2);
    }
    let sources: Vec<PathBuf> = std::fs::read_dir(&dir)
        .unwrap()
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| p.extension().and_then(|s| s.to_str()) == Some("cbz"))
        .collect();
    assert_eq!(sources.len(), 7);

    rust_core::merge::merge_chapters(&dir, true /* delete */, false, None, None);

    assert_eq!(volume_files(&dir, "Del").len(), 1, "one volume produced");
    let remaining: Vec<_> = std::fs::read_dir(&dir)
        .unwrap()
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| p.extension().and_then(|s| s.to_str()) == Some("cbz"))
        .collect();
    assert_eq!(remaining.len(), 1, "source chapters removed when delete=true");
}
