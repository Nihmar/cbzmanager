//! Validation service (deep) — per-image checks must be identical regardless of
//! the number of decode threads (parallel rayon path is order-preserving).

mod common;
use common::*;

use std::path::PathBuf;

use rust_core::validate::{validate_deep, FileValidationResult};

fn tempdir(tag: &str) -> PathBuf {
    let mut d = std::env::temp_dir();
    d.push(format!("cbztest_{}_{}_{}", tag, std::process::id(), std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos()));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).unwrap();
    d
}

/// Compare two FileValidationResult batches field by field so any ordering or
/// content drift surfaces as a precise assertion failure.
fn results_equal(a: &[FileValidationResult], b: &[FileValidationResult]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    a.iter().zip(b).all(|(x, y)| {
        x.file_name == y.file_name
            && x.valid == y.valid
            && x.image_count == y.image_count
            && x.error_msg == y.error_msg
            && x.image_checks.len() == y.image_checks.len()
            && x
                .image_checks
                .iter()
                .zip(&y.image_checks)
                .all(|(p, q)| {
                    p.filename == q.filename
                        && p.ok == q.ok
                        && p.errors == q.errors
                        && p.depth == q.depth
                })
    })
}

#[test]
fn validate_deep_is_deterministic_across_threads() {
    let dir = tempdir("uservicevalidate");

    // Two real PNG pages plus one deliberately corrupt "image" so both the ok
    // and non-ok branches are exercised by every thread count.
    let mut pages: Vec<Vec<u8>> = vec![make_png(8, 8, 1), make_noise_png(8, 8, 7)];
    pages.push(b"this is not an image".to_vec());
    make_cbz(&dir, "Volume.cbz", &pages);

    let files = vec![dir.join("Volume.cbz")];

    let r1 = validate_deep(&dir, &files, 1);
    let r4 = validate_deep(&dir, &files, 4);

    assert_eq!(r1.len(), 1, "one archive validated");
    assert_eq!(r1[0].image_checks.len(), 3, "two pages + one corrupt entry");
    // Page index 2 is the intentionally-corrupt page: exactly one failure.
    let ok_count = r1[0].image_checks.iter().filter(|c| c.ok).count();
    assert_eq!(ok_count, 2);

    assert!(results_equal(&r1, &r4), "thread count changed results");
}

#[test]
fn validate_deep_empty_archive_reports_no_images() {
    let dir = tempdir("uservicevalidate_empty");
    // CBZ with a non-image entry only (ComicInfo.xml is filtered out).
    make_cbz(&dir, "Empty.cbz", &[]);
    let files = vec![dir.join("Empty.cbz")];

    let r1 = validate_deep(&dir, &files, 1);
    let r8 = validate_deep(&dir, &files, 8);

    assert_eq!(r1[0].image_count, 0);
    assert!(!r1[0].valid);
    assert!(results_equal(&r1, &r8), "thread count changed results");
}
