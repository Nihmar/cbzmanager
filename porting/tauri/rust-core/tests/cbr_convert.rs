//! CBR → CBZ batch service integration tests — GAPS 1.1–1.3.
//!
//! These deliberately avoid libarchive: each fixture is a real ZIP whose name
//! ends in `.cbr`, so `process_cbr` takes the ZIP fallback path (RAR detection
//! fails and it falls back to `collect_zip_entries_all`). The test crate is only
//! compiled with `--features cbr`.

mod common;

use std::path::{Path, PathBuf};

use common::*;
use rust_core::cbr_convert::convert_cbr_to_cbz;
use rust_core::zip_ops::{get_entry_names, read_entry, write_zip_from_entries, ZipEntry};

fn tempdir(tag: &str) -> PathBuf {
    let mut d = std::env::temp_dir();
    d.push(format!(
        "cbzcbr_{}_{}_{:?}",
        tag,
        std::process::id(),
        std::thread::current().id()
    ));
    std::fs::create_dir_all(&d).unwrap();
    d
}

fn target_for(dir: &Path, base: &str) -> PathBuf {
    dir.join(format!("{}.cbz", base))
}

/// Full paths for the `.cbr` files in `dir` (sorted like the service expects).
fn cbr_paths(dir: &Path) -> Vec<PathBuf> {
    use rust_core::cbr_convert::collect_cbr_files;
    collect_cbr_files(dir)
        .iter()
        .map(|f| dir.join(f))
        .collect()
}

/// Write a valid ZIP whose name ends in `.cbr` (ZIP fallback path, no libarchive).
fn fake_cbr(dir: &Path, name: &str, pages: &[Vec<u8>]) -> PathBuf {
    let mut entries: Vec<ZipEntry> = pages
        .iter()
        .enumerate()
        .map(|(i, p)| ZipEntry::new(format!("page_{:04}.png", i + 1), p.clone()))
        .collect();
    entries.push(ZipEntry::new("ComicInfo.xml", b"<ComicInfo/>".to_vec()));
    let path = dir.join(name);
    write_zip_from_entries(&path, &entries).expect("write fake cbr");
    path
}

#[test]
fn keep_source_writes_cbz_with_renamed_pages() {
    let dir = tempdir("keep");
    fake_cbr(&dir, "Series - 0001.cbr", &[make_png(4, 4, 1), make_png(4, 4, 2)]);

    let results = convert_cbr_to_cbz(&dir, &cbr_paths(&dir), 1, false, false);
    assert_eq!(results.len(), 1);
    let r = &results[0];
    assert!(r.converted, "conversion succeeded: {}", r.error_msg);
    assert!(r.error_msg.is_empty());

    // Source retained; target written next to it.
    assert!(dir.join("Series - 0001.cbr").exists(), "source kept when delete=false");
    let cbz = target_for(&dir, "Series - 0001");
    assert!(cbz.exists(), ".cbz written next to source");

    let names: Vec<String> = get_entry_names(&cbz).unwrap();
    // ComicInfo.xml filtered; pages renumbered sequentially (extension case preserved).
    assert_eq!(names, vec!["page_001.png".to_string(), "page_002.png".to_string()]);
}

#[test]
fn delete_source_removes_the_cbr_after_write() {
    let dir = tempdir("del");
    fake_cbr(&dir, "Series - 0002.cbr", &[make_png(4, 4, 1)]);

    convert_cbr_to_cbz(&dir, &cbr_paths(&dir), 1, true, false);

    assert!(!dir.join("Series - 0002.cbr").exists(), "source removed when delete=true");
    assert!(target_for(&dir, "Series - 0002").exists());
}

#[test]
fn skip_existing_ignores_an_existing_target() {
    let dir = tempdir("skip");
    let cbr = fake_cbr(&dir, "Series - 0003.cbr", &[make_png(4, 4, 1), make_png(4, 4, 2)]);

    // Pre-create the target with a marker entry.
    write_zip_from_entries(
        &target_for(&dir, "Series - 0003"),
        &[ZipEntry::new("marker.png", make_png(2, 2, 9))],
    )
    .unwrap();
    let original = get_entry_names(&target_for(&dir, "Series - 0003")).unwrap();

    let results = convert_cbr_to_cbz(&dir, &vec![cbr.clone()], 1, false, true);
    assert_eq!(results.len(), 1);
    let r = &results[0];
    assert!(!r.converted, "skipped file is not converted");
    assert!(!r.error_msg.is_empty(), "skip reported via error message");

    // The pre-existing target was left untouched.
    let after = get_entry_names(&target_for(&dir, "Series - 0003")).unwrap();
    assert_eq!(original, after, "existing target not overwritten");
}

#[test]
fn thread_count_is_capped_and_output_deterministic() {
    let dir1 = tempdir("t1");
    let dir64 = tempdir("t64");
    for d in [&dir1, &dir64] {
        fake_cbr(
            d,
            "A - 0001.cbr",
            &[make_png(8, 8, 3), make_png(8, 8, 4), make_png(8, 8, 5)],
        );
    }

    convert_cbr_to_cbz(&dir1, &cbr_paths(&dir1), 1, false, false);
    // threads=64 far exceeds MAX_CBR_THREADS (4) — must be capped internally.
    convert_cbr_to_cbz(&dir64, &cbr_paths(&dir64), 64, false, false);

    let a = target_for(&dir1, "A - 0001");
    let b = target_for(&dir64, "A - 0001");
    // Byte-identical content regardless of the (capped) thread count.
    let names_a = get_entry_names(&a).unwrap();
    let names_b = get_entry_names(&b).unwrap();
    assert_eq!(names_a, names_b);
    for n in &names_a {
        assert_eq!(read_entry(&a, n).unwrap(), read_entry(&b, n).unwrap());
    }
}
