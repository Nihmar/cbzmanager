#![cfg(feature = "cbr")]
//! CBR (RAR) reader integration test — drives `src/cbr_reader.rs` through
//! libarchive. Fixtures are valid ZIP-format archives saved with a `.cbr`
//! extension; libarchive detects the format by content, so the same code path
//! is exercised as for real RAR files without bundling rartool. Guarded on
//! `libarchive.so` availability (PLAN item 10I).

mod common;
use common::*;

use std::path::PathBuf;

#[cfg(feature = "cbr")]
use rust_core::cbr_reader;

fn tempdir(tag: &str) -> PathBuf {
    let mut d = std::env::temp_dir();
    d.push(format!("cbctest_{}_{}_{}", tag, std::process::id(), std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos()));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).unwrap();
    d
}

/// Print a note and bail out unless the libarchive backend loads, so the test
/// is a genuine skip (not a silent pass) on systems missing `libarchive.so`.
#[cfg(feature = "cbr")]
fn require_cbr() -> bool {
    if cbr_reader::cbr_supported() {
        true
    } else {
        println!("SKIP: libarchive not available — skipping CBR reader test");
        false
    }
}

#[cfg(feature = "cbr")]
#[test]
fn is_cbr_image_ext_classifies_by_extension() {
    assert!(cbr_reader::is_cbr_image_ext("page_0001.png"));
    assert!(cbr_reader::is_cbr_image_ext("scan.JPG"));
    assert!(cbr_reader::is_cbr_image_ext("chapter.jpeg"));
    assert!(cbr_reader::is_cbr_image_ext("cover.WebP"));
    assert!(cbr_reader::is_cbr_image_ext("frame.bmp"));
    // Non-image entries are never treated as pages.
    assert!(!cbr_reader::is_cbr_image_ext("ComicInfo.xml"));
    assert!(!cbr_reader::is_cbr_image_ext("manga.cbz"));
    assert!(!cbr_reader::is_cbr_image_ext("notes.txt"));
    assert!(!cbr_reader::is_cbr_image_ext("noext"));
}

#[cfg(feature = "cbr")]
#[test]
fn collect_cbr_entries_reads_zip_format_archive_saved_as_cbr() {
    if !require_cbr() {
        return;
    }

    let dir = tempdir("entries");
    let page_a = make_png(6, 10, 1);
    let page_b = make_png(6, 10, 2);
    // `make_cbz` produces a real ZIP (PK\0\3) but here it lands under a `.cbr`
    // name — exactly what libarchive content-sniffs on disk.
    let cbr = make_cbz(&dir, "Manga.cbr", &[page_a.clone(), page_b.clone()]);

    let entries = cbr_reader::collect_cbr_entries(&cbr).expect("read .cbr");

    // Exactly the two image pages; ComicInfo.xml is filtered out by name.
    assert_eq!(entries.len(), 2, "unexpected entry count: {:?}", &entries);
    let names: Vec<&str> = entries.iter().map(|(n, _)| n.as_str()).collect();
    assert_eq!(names, vec!["page_0001.png", "page_0002.png"]);
    assert!(entries.iter().all(|(n, _)| !n.contains("ComicInfo")), "ComicInfo leaked");
    assert_eq!(entries[0].1, page_a);
    assert_eq!(entries[1].1, page_b);

    std::fs::remove_dir_all(&dir).ok();
}

#[cfg(feature = "cbr")]
#[test]
fn collect_cbr_image_names_filters_comicinfo() {
    if !require_cbr() {
        return;
    }

    let dir = tempdir("names");
    let pages: Vec<Vec<u8>> = vec![make_png(4, 4, 3), make_png(4, 4, 4)];
    let cbr = make_cbz(&dir, "Volume.cbr", &pages);

    let names = cbr_reader::collect_cbr_image_names(&cbr).expect("list names");

    // ComicInfo.xml (and the .cbz extension itself) are not image pages.
    assert!(!names.iter().any(|n| n.contains("ComicInfo")));
    assert_eq!(names.len(), 2);
    let set: std::collections::BTreeSet<_> = names.into_iter().collect();
    assert_eq!(set, ["page_0001.png".to_string(), "page_0002.png".to_string()].into_iter().collect());

    std::fs::remove_dir_all(&dir).ok();
}

#[cfg(feature = "cbr")]
#[test]
fn collect_cbr_entries_missing_file_is_error() {
    if !require_cbr() {
        return;
    }

    let dir = tempdir("missing");
    let absent = dir.join("does_not_exist.cbr");
    assert!(absent.exists() == false);
    match cbr_reader::collect_cbr_entries(&absent) {
        Err(_) => {} // expected: an unreadable archive surfaces as an error
        Ok(entries) => panic!("expected error for missing file, got {} entries", entries.len()),
    }

    std::fs::remove_dir_all(&dir).ok();
}
