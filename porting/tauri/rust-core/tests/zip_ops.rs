mod common;

use std::path::PathBuf;

use common::*;

fn tempdir(tag: &str) -> PathBuf {
    let mut d = std::env::temp_dir();
    d.push(format!(
        "cbztest_{}_{}_{:?}",
        tag,
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos(),
        std::thread::current().id()
    ));
    std::fs::create_dir_all(&d).unwrap();
    d
}

#[test]
fn collect_filters_comicinfo_but_keeps_images() {
    let dir = tempdir("collect");
    let pages = [make_png(6, 6, 1), make_png(6, 6, 2), make_png(6, 6, 3)];
    let cbz = make_cbz(&dir, "a.cbz", &pages);

    let entries = rust_core::zip_ops::collect_zip_entries(&cbz).expect("collect");
    let names: Vec<String> = entries.iter().map(|e| e.name.clone()).collect();

    assert_eq!(names.len(), 3, "ComicInfo.xml must be filtered out");
    assert!(names.iter().all(|n| n != "ComicInfo.xml"), "no comicinfo leaked");
    assert!(names.contains(&"page_0001.png".to_string()));
}

#[test]
fn collect_all_keeps_comicinfo() {
    let dir = tempdir("collectall");
    let cbz = make_cbz(&dir, "a.cbz", &[make_png(4, 4, 1), make_png(4, 4, 2)]);

    let entries = rust_core::zip_ops::collect_zip_entries_all(&cbz).expect("collect all");
    assert_eq!(entries.len(), 3, "comicinfo should be kept by _all variant");
    assert!(entries.iter().any(|e| e.is_comicinfo()));
}

#[test]
fn count_image_entries_ignores_non_images() {
    let dir = tempdir("count");
    make_cbz(&dir, "a.cbz", &[make_png(4, 4, 1), make_png(4, 4, 2)]);
    // ComicInfo.xml is present in the archive but not an image.
    assert_eq!(rust_core::zip_ops::count_image_entries(&dir.join("a.cbz")).unwrap(), 2);
}

#[test]
fn is_image_entry_classifies_extensions() {
    assert!(rust_core::zip_ops::is_image_entry("page_0001.png"));
    assert!(rust_core::zip_ops::is_image_entry("scan.JPEG"));
    assert!(!rust_core::zip_ops::is_image_entry("ComicInfo.xml"));
    assert!(!rust_core::zip_ops::is_image_entry("credits.txt"));
}

#[test]
fn renumber_is_one_based_and_keeps_comicinfo() {
    let dir = tempdir("renumber");
    let cbz = make_cbz(&dir, "a.cbz", &[make_png(4, 4, 1), make_png(4, 4, 2), make_png(4, 4, 3)]);

    // Scramble the entry order (descending) so renumber must sort by content.
    let mut entries = rust_core::zip_ops::collect_zip_entries_all(&cbz).unwrap();
    entries.sort_by(|a, b| b.name.cmp(&a.name));

    rust_core::zip_ops::renumber_entries(&mut entries, true);

    let names: Vec<String> = entries.iter().map(|e| e.name.clone()).collect();
    assert_eq!(
        names,
        vec![
            "page_001.png".to_string(),
            "page_002.png".to_string(),
            "page_003.png".to_string(),
            "ComicInfo.xml".to_string()
        ],
        "pages renumber 1-based in archive order (names reassigned by position); comicinfo preserved"
    );
}

#[test]
fn strip_comicinfo_removes_the_entry() {
    let dir = tempdir("strip");
    let cbz = make_cbz(&dir, "a.cbz", &[make_png(4, 4, 1)]);
    let mut entries = rust_core::zip_ops::collect_zip_entries_all(&cbz).unwrap();
    let removed = rust_core::zip_ops::strip_comicinfo(&mut entries);
    assert_eq!(removed, 1);
    assert!(!entries.iter().any(|e| e.is_comicinfo()));
}

#[test]
fn roundtrip_preserves_entry_content() {
    let dir = tempdir("roundtrip");
    let pages = [make_png(8, 8, 5), make_png(8, 8, 9)];
    let src = make_cbz(&dir, "src.cbz", &pages);

    let entries = rust_core::zip_ops::collect_zip_entries(&src).unwrap();
    let dst = dir.join("dst.cbz");
    rust_core::zip_ops::write_zip_from_entries(&dst, &entries).unwrap();

    let back = rust_core::zip_ops::collect_zip_entries(&dst).unwrap();
    assert_eq!(entries.len(), back.len());
    for (a, b) in entries.iter().zip(back.iter()) {
        assert_eq!(a.name, b.name);
        assert_eq!(a.data, b.data, "content must survive a round trip");
    }
}

#[test]
fn is_valid_cbz_checks_image_count() {
    let dir = tempdir("valid");
    let good = make_cbz(&dir, "good.cbz", &[make_png(4, 4, 1)]);
    // Archive with zero images (only comicinfo) is not a valid CBZ.
    let empty = dir.join("empty.cbz");
    rust_core::zip_ops::write_zip_from_entries(
        &empty,
        &[rust_core::zip_ops::ZipEntry::new("ComicInfo.xml", b"<x/>".to_vec())],
    )
    .unwrap();
    assert!(rust_core::zip_ops::is_valid_cbz(&good).unwrap());
    assert!(!rust_core::zip_ops::is_valid_cbz(&empty).unwrap());
}
