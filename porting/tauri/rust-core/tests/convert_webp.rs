mod common;

use std::path::{Path, PathBuf};

use common::*;

fn tempdir(tag: &str) -> PathBuf {
    let mut d = std::env::temp_dir();
    d.push(format!("cbztest_{}_{}", tag, std::process::id()));
    std::fs::create_dir_all(&d).unwrap();
    d
}

/// Seed two sibling directories with identical CBZ content (noise PNGs + comicinfo)
/// so two convert runs can be compared byte-for-byte.
fn seed_two_dirs(tag: &str) -> (PathBuf, PathBuf) {
    let a = tempdir(&format!("{}a", tag));
    let b = tempdir(&format!("{}b", tag));
    let pages = [
        make_noise_png(48, 48, 1),
        make_noise_png(48, 48, 2),
        make_noise_png(48, 48, 3),
    ];
    for (i, d) in [a.clone(), b.clone()].into_iter().enumerate() {
        let _ = i;
        make_cbz(&d, "volume.cbz", &pages);
    }
    (a, b)
}

/// Compare two archives entry-by-entry, ignoring ZIP internal metadata and
/// timestamps — content equality is the determinism guarantee.
fn archives_content_equal(a: &Path, b: &Path) -> bool {
    let ea = rust_core::zip_ops::collect_zip_entries_all(a).ok();
    let eb = rust_core::zip_ops::collect_zip_entries_all(b).ok();
    match (ea, eb) {
        (Some(x), Some(y)) => x.len() == y.len()
            && x.iter().zip(y.iter()).all(|(p, q)| p.name == q.name && p.data == q.data),
        _ => false,
    }
}

#[test]
fn convert_webp_deterministic_across_threads() {
    let (dir_a, dir_b) = seed_two_dirs("conv");
    let file_a = dir_a.join("volume.cbz");
    let file_b = dir_b.join("volume.cbz");

    // Same input bytes, different worker counts.
    let files1 = vec![file_a.clone()];
    let files4 = vec![file_b.clone()];

    let r1 = rust_core::convert_webp::convert_webp(&dir_a, &files1, 1, false);
    let r4 = rust_core::convert_webp::convert_webp(&dir_b, &files4, 4, false);

    assert_eq!(r1.len(), 1);
    assert_eq!(r4.len(), 1);
    // Both ran the same work; report conversion consistently.
    assert_eq!(r1[0].converted, r4[0].converted);

    let out_a = dir_a.join("volume.cbz");
    let out_b = dir_b.join("volume.cbz");
    assert!(
        archives_content_equal(&out_a, &out_b),
        "parallel WebP conversion must be byte-identical regardless of thread count"
    );

    // Noise PNGs compress to smaller WebP, so pages are converted (not kept).
    let out_a_names: Vec<String> = rust_core::zip_ops::get_entry_names(&out_a).unwrap();
    assert!(out_a_names.iter().all(|n| n.ends_with(".webp")), "noise converts to webp");
}

#[test]
fn convert_backs_up_original_when_not_deleting() {
    let dir = tempdir("convbackup");
    make_cbz(&dir, "volume.cbz", &[make_noise_png(48, 48, 7), make_noise_png(48, 48, 8)]);
    let orig = dir.join("volume.cbz");

    rust_core::convert_webp::convert_webp(&dir, &vec![orig.clone()], 2, false);

    assert!(
        orig.parent().unwrap().join("volume_OLD.cbz").exists(),
        "_OLD.cbz backup must exist when delete_source is false"
    );
}

#[test]
fn convert_deletes_source_when_requested() {
    let dir = tempdir("convdelete");
    make_cbz(&dir, "volume.cbz", &[make_noise_png(48, 48, 11), make_noise_png(48, 48, 12)]);
    let orig = dir.join("volume.cbz");

    rust_core::convert_webp::convert_webp(&dir, &vec![orig.clone()], 2, true);

    // --delete means: overwrite in place with no _OLD backup (the "source" that
    // is deleted is the original *bytes*, replaced by the converted output).
    assert!(orig.exists(), "converted archive is written in place");
    assert!(
        !orig.parent().unwrap().join("volume_OLD.cbz").exists(),
        "no _OLD backup created when delete_source is true"
    );
}

#[test]
fn convert_renumbers_pages_sequentially() {
    let dir = tempdir("convrenumber");
    // Non-sequential source names exercise the renumbering on output.
    use rust_core::zip_ops::{write_zip_from_entries, ZipEntry};
    let entries = vec![
        ZipEntry::new("aaa.png", make_noise_png(40, 40, 1)),
        ZipEntry::new("zzz.png", make_noise_png(40, 40, 2)),
        ZipEntry::new("mmm.png", make_noise_png(40, 40, 3)),
    ];
    write_zip_from_entries(&dir.join("volume.cbz"), &entries).unwrap();

    rust_core::convert_webp::convert_webp(&dir, &[dir.join("volume.cbz")], 1, true);

    let names = cbz_names(&dir.join("volume.cbz"));
    assert_eq!(names.len(), 3, "comicinfo stays out of the way; all images kept");
    // Noise PNGs convert to smaller WebP, so survivor pages are renumbered as .webp.
    assert_eq!(names[0], "page_0001.webp", "renumbered sequentially in original order");
    assert_eq!(names[1], "page_0002.webp");
    assert_eq!(names[2], "page_0003.webp");
}
