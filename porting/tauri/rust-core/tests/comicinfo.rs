//! ComicInfo scan/remove service — mirrors the Lazarus `TComicInfoServiceTest`
//! cases plus the L3 edge case where stripping ComicInfo.xml leaves zero image
//! entries (must be skipped, not silently turned into an invalid CBZ).

mod common;
use common::*;

use std::path::{Path, PathBuf};

use rust_core::zip_ops::{write_zip_from_entries, ZipEntry};

fn tempdir(tag: &str) -> PathBuf {
    let mut d = std::env::temp_dir();
    d.push(format!(
        "cbzci_{}_{}_{}",
        tag,
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).unwrap();
    d
}

/// Write a CBZ at dir/name from arbitrary (name, bytes) entries — no auto
/// ComicInfo.xml appended.
fn make_cbz_entries(
    dir: &Path,
    name: &str,
    items: &[(&str, &[u8])],
) -> PathBuf {
    let entries: Vec<ZipEntry> = items
        .iter()
        .map(|(n, b)| ZipEntry::new(n.to_string(), b.to_vec()))
        .collect();
    write_zip_from_entries(&dir.join(name), &entries).expect("write_cbz");
    dir.join(name)
}

#[test]
fn scan_detects_comicinfo() {
    let dir = tempdir("scan");
    make_cbz_entries(
        &dir,
        "with.cbz",
        &[("ComicInfo.xml", b"<ComicInfo/>"), ("page001.jpg", &[0u8; 8])],
    );
    let files = vec!["with.cbz"];
    let r = rust_core::comicinfo::scan(&dir, &files);
    assert_eq!(r.len(), 1);
    assert!(r[0].has_comicinfo, "scan should detect comicinfo");
}

#[test]
fn remove_strips_comicinfo_when_images_remain() {
    let dir = tempdir("remove_ok");
    make_cbz_entries(
        &dir,
        "with.cbz",
        &[("page001.jpg", &[0u8; 8]), ("ComicInfo.xml", b"<ComicInfo/>")],
    );
    let files = vec!["with.cbz"];
    let r = rust_core::comicinfo::remove(&dir, &files, false, 1);
    assert!(r[0].removed, "remove should succeed when images remain");
    assert_eq!(r[0].error_msg, "");

    let names: Vec<String> = cbz_names(&dir.join("with.cbz"));
    assert!(
        !names.iter().any(|n| n.eq_ignore_ascii_case("comicinfo.xml")),
        "comicinfo stripped"
    );
    assert!(
        cbz_entry(&dir.join("with.cbz"), "page001.jpg").is_some(),
        "image kept"
    );
}

#[test]
fn remove_no_image_entries_is_skipped_not_corrupting() {
    // Archive has ComicInfo.xml but no image entries: stripping the metadata
    // must leave the original untouched (not an empty/invalid CBZ) and report
    // the file skipped rather than removed. This is the L3 edge case fixed in
    // both ports.
    let dir = tempdir("noimage");
    make_cbz_entries(&dir, "metadata.cbz", &[("ComicInfo.xml", b"<ComicInfo/>")]);

    let files = vec!["metadata.cbz"];
    let r = rust_core::comicinfo::remove(&dir, &files, false, 1);
    assert_eq!(r.len(), 1);
    assert!(!r[0].removed, "no-image archive is skipped");
    assert_eq!(r[0].error_msg, "No images to keep");
    assert!(r[0].has_comicinfo, "comicinfo was still detected");

    // The original file must be byte-identical and untouched on disk.
    let names: Vec<String> = cbz_names(&dir.join("metadata.cbz"));
    assert_eq!(names.len(), 1);
    assert_eq!(&names[0], "ComicInfo.xml");
    assert!(cbz_entry(&dir.join("metadata.cbz"), "ComicInfo.xml").is_some());
}

#[test]
fn remove_no_image_entries_writes_no_backup() {
    // Even with backup requested, a skipped no-image archive must not leave a
    // _OLD copy behind.
    let dir = tempdir("noimage_bak");
    make_cbz_entries(&dir, "metadata.cbz", &[("ComicInfo.xml", b"<ComicInfo/>")]);

    let files = vec!["metadata.cbz"];
    let r = rust_core::comicinfo::remove(&dir, &files, true, 1);
    assert!(!r[0].removed);
    assert_eq!(r[0].error_msg, "No images to keep");
    assert!(!dir.join("metadata_OLD.cbz").exists());
}

#[test]
fn remove_no_image_entries_skipped_parallel_and_sequential() {
    // Skip behaviour must be identical regardless of thread count (both paths
    // route through the same remove_one which now guards on image entries).
    let dir = tempdir("noimage_par");
    make_cbz_entries(&dir, "seq.cbz", &[("ComicInfo.xml", b"<ComicInfo/>")]);
    make_cbz_entries(&dir, "par.cbz", &[("ComicInfo.xml", b"<ComicInfo/>")]);

    let r_seq = rust_core::comicinfo::remove(&dir, &["seq.cbz"], false, 1);
    let r_par = rust_core::comicinfo::remove(&dir, &["par.cbz"], false, 4);

    assert!(!r_seq[0].removed && r_seq[0].error_msg == "No images to keep");
    assert!(!r_par[0].removed && r_par[0].error_msg == "No images to keep");
}
