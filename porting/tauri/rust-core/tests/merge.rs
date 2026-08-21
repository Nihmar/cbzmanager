//! Merge service integration tests — classification, CPV batching and the
//! documented "not-enough-chapters → no volume" divergence (matches the Python
//! reference: `num_volumes = int(num_chapters / chapters_per_volume)`, skipped
//! when zero).

mod common;

use std::path::{Path, PathBuf};

use common::*;
use proptest::prelude::*;

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

// ---------------------------------------------------------------------------
// Property test — random chapter sets vs an independent oracle of the Python
// reference semantics (`porting/cbz_manager/src/cbz_manager/merge.py`).
//
// For each generated series we know its exact inputs (chapter numbers, page
// counts, number of pre-existing volumes), so the oracle computes the expected
// result — classification, CPV derivation, batching and sequential renumbering
// — without touching `parse_cbz_files`/`merge_chapters`. The implementation is
// then asserted to agree on the same inputs. This exercises both CPV paths
// (default 7 when no volumes; `(lowest-1)/n_existing` when volumes exist) via
// proptest's randomized chapter/pair generation.
// ---------------------------------------------------------------------------

/// One generated series: name, its chapters (chapter number, page count) and the
/// number of pre-existing `"{name} V{nnn}.cbz"` volume files.
struct GenSpec {
    name: String,
    chapters: Vec<(i32, usize)>,
    num_existing_vols: usize,
}

fn expected_plan(series: &str, ch: &[(i32, usize)], n_vols: usize) -> Option<PlanEntry> {
    if ch.is_empty() {
        return None; // no chapters => the series is skipped entirely.
    }
    let mut sorted: Vec<(i32, usize)> = ch.to_vec();
    sorted.sort_by_key(|e| e.0);
    let lowest = sorted.first().map(|e| e.0).unwrap_or(0);

    // Mirror Rust/Python: default CPV 7 with no volumes, else
    // (lowest_chapter - 1) / num_existing_volumes.
    let cpv: f64 = if n_vols == 0 {
        7.0
    } else {
        (lowest - 1) as f64 / n_vols as f64
    };

    // Volumes-only series (or CPV < 1) are skipped — no volume is produced.
    if cpv < 1.0 {
        return None;
    }

    let num_new = (sorted.len() as f64 / cpv) as usize;
    if num_new == 0 {
        return None;
    }

    let batch = cpv as usize; // integer chapters per volume
    let next_vol = if n_vols == 0 {
        1
    } else {
        (n_vols as i32) + 1
    };

    let mut produced: Vec<VolumePlan> = Vec::new();
    let mut idx = 0usize;
    for k in 0..num_new {
        let start = idx;
        let end = std::cmp::min(idx + batch, sorted.len());
        if start >= end {
            break;
        }
        let page_count: usize = (start..end).map(|i| ch[i].1).sum();
        produced.push(VolumePlan {
            title: format!("{} V{:03}.cbz", series, next_vol + k as i32),
            chapter_count: end - start,
            page_count,
        });
        idx = end;
    }

    let total_pages: usize = produced.iter().map(|v| v.page_count).sum();
    Some(PlanEntry {
        volumes_created: num_new,
        total_pages,
        volumes: produced,
    })
}

#[allow(dead_code)]
#[derive(Debug)]
struct VolumePlan {
    title: String,
    chapter_count: usize,
    page_count: usize,
}

#[allow(dead_code)]
#[derive(Debug)]
struct PlanEntry {
    volumes_created: usize,
    total_pages: usize,
    volumes: Vec<VolumePlan>,
}

#[allow(dead_code)]
fn expected_results(specs: &[GenSpec]) -> Vec<(String, PlanEntry)> {
    let mut all: Vec<(String, PlanEntry)> = specs
        .iter()
        .map(|s| (s.name.clone(), s.chapters.clone(), s.num_existing_vols))
        .filter_map(|(name, ch, n)| expected_plan(&name, &ch, n).map(|p| (name, p)))
        .collect();
    all.sort_by(|a, b| a.0.cmp(&b.0)); // Rust sorts result series names ascending
    all.into_iter().collect()
}

/// Random series label using letters only — no `-` or spaces — so the filename
/// pattern never ambiguously classifies in `parse_cbz_files`.
#[allow(dead_code)]
fn base_name() -> impl proptest::strategy::Strategy<Value = String> {
    let chars = prop::collection::vec((b'a'..=b'z').prop_map(|c| c as char), 1..6);
    chars.prop_map(|v: Vec<char>| v.into_iter().collect::<String>())
}

/// One (label, chapters) pair. Chapter numbers come from a hash set so they are
/// unique within a spec — no two files with the same `Series - NNNN.cbz` name —
/// and page counts are derived from the number to stay in 1..=8.
#[allow(dead_code)]
fn one_spec() -> impl proptest::strategy::Strategy<Value = (String, Vec<(i32, usize)>)> {
    let caps = prop::collection::hash_set(1..=50i32, 0..=20usize);
    (base_name(), caps).prop_map(|(n, set)| {
        (
            n,
            set.into_iter()
                .map(|num| (num, ((num % 8) + 1) as usize))
                .collect::<Vec<_>>(),
        )
    })
}

#[test]
fn merge_chapters_matches_reference_on_random_inputs() {
    proptest! {
        fn random_merge(
            per_spec in prop::collection::vec(one_spec(), 1..=4usize),
            vols in prop::collection::vec(0..=3usize, 1..=4usize),
        ) {
            // Unique series names (suffix the index) so filenames never collide.
            // The first series always carries >=1 existing volume to exercise the
            // derived-CPV path on every run; others fall back to a random count
            // (default CPV 7 when zero).
            let mut specs: Vec<GenSpec> = Vec::new();
            for (i, (base, ch)) in per_spec.iter().enumerate() {
                let name = format!("{}{}", base, i + 1);
                let raw_vols = vols
                    .get(i.saturating_sub(1))
                    .copied()
                    .unwrap_or(0);
                let num_existing_vols = if i == 0 { raw_vols.max(1) } else { raw_vols };
                specs.push(GenSpec { name, chapters: ch.clone(), num_existing_vols });
            }

            // Write fixtures. ComicInfo.xml is appended by make_cbz so the merge's
            // filter path is exercised too.
            let dir = tempdir("prop");
            for s in &specs {
                for (num, pages) in &s.chapters {
                    let imgs: Vec<Vec<u8>> = (0..*pages).map(|p| make_png(4, 4, p as u8)).collect();
                    let entries: Vec<rust_core::zip_ops::ZipEntry> = imgs
                        .iter()
                        .enumerate()
                        .map(|(j, b)| rust_core::zip_ops::ZipEntry::new(format!("page_{:04}.png", j + 1), b.clone()))
                        .collect();
                    rust_core::zip_ops::write_zip_from_entries(
                        &dir.join(format!("{} - {:04}.cbz", s.name, num)),
                        &entries,
                    )
                    .unwrap();
                }
                for t in 1..=s.num_existing_vols {
                    let entries = vec![rust_core::zip_ops::ZipEntry::new("page_0001.png", make_png(2, 2, 1))];
                    rust_core::zip_ops::write_zip_from_entries(
                        &dir.join(format!("{} V{:03}.cbz", s.name, t)),
                        &entries,
                    )
                    .unwrap();
                }
            }

            // Compute the expected plan independently of the implementation.
            let exp = expected_results(&specs);

            let res = rust_core::merge::merge_chapters(&dir, false, false, None, None);
            assert_eq!(res.len(), exp.len());

            for (i, ((name, pe), actual)) in exp.iter().zip(res.iter()).enumerate() {
                assert_eq!(name.as_str(), &actual.series_name, "series order {}", i);
                assert_eq!(pe.volumes_created, actual.volumes_created, "volume count {} in {}", i, name);
                assert_eq!(pe.total_pages, actual.total_pages, "total pages {} in {}", i, name);
                assert!(actual.error_msg.is_empty(), "unexpected error for {}: {}", i, name);

                let titles: Vec<String> = actual.volumes.iter().map(|v| v.title.clone()).collect();
                assert_eq!(titles.len(), pe.volumes.len());
                for (k, vp) in pe.volumes.iter().enumerate() {
                    assert_eq!(vp.title.as_str(), &titles[k], "volume title {} of {}", k, name);
                    assert_eq!(
                        vp.chapter_count,
                        actual.volumes[k].chapters.len(),
                        "chapter count {} in {}",
                        k,
                        name
                    );

                    // Content-level check: sequential renumbering with padding
                    // = max(3, len(str(volume_page_count)), comicinfo filtered.
                    let names = cbz_names(&actual.volumes[k].output_path);
                    let pages = vp.page_count;
                    assert_eq!(names.len(), pages, "merged page count {} of {}", k, name);
                    assert!(!names.iter().any(|n| n == "ComicInfo.xml"), "comicinfo filtered in {}", name);
                    let width = std::cmp::max(3, format!("{}", pages).len());
                    for (idx, n) in names.iter().enumerate() {
                        assert_eq!(
                            n,
                            &format!("page_{:0>width$}.png", idx as u32 + 1),
                            "renumber in {} volume {}",
                            name,
                            k
                        );
                    }
                }
            }
        }
    }
}
