//! Batch-edit pipeline unit tests: neutral no-op, percent resize, colour, split
//! piece counts, output-extension mapping and Data-stream precedence. Mirrors
//! `ubatchedit.pas` (ApplyMultiEditToImage).

mod common;

use image::DynamicImage;

use common::*;

fn decode_page(tag: &str) -> DynamicImage {
    image::load_from_memory(&make_png(8, 8, tag.as_bytes()[0] % 200)).unwrap()
}

#[test]
fn params_neutral_reports_no_change() {
    assert!(rust_core::batch_edit::MultiEditParams::neutral().is_neutral());
    let mut p = rust_core::batch_edit::MultiEditParams::neutral();
    p.percent = 100; // still neutral when percent==100 and resize flag set
    assert!(p.is_neutral());

    p.resize = true;
    p.percent = 50;
    assert!(!p.is_neutral(), "percent != 100 is a real change");
}

#[test]
fn neutral_params_encode_single_piece() {
    let img = decode_page("neut");
    let pieces = rust_core::batch_edit::apply_edit_to_image(&img, &rust_core::batch_edit::MultiEditParams::neutral(), "png");
    assert!(pieces.1, "neutral apply succeeds");
    assert_eq!(pieces.0.len(), 1);
    assert_eq!(pieces.0[0].ext, "png");
}

#[test]
fn percent_resize_changes_output_dimensions() {
    let img = decode_page("resz"); // 8x8
    let mut p = rust_core::batch_edit::MultiEditParams::neutral();
    p.resize = true;
    p.percent = 50;

    let (pieces, ok) = rust_core::batch_edit::apply_edit_to_image(&img, &p, "png");
    assert!(ok);
    assert_eq!(pieces.len(), 1);
    // Encoded as lossless PNG so dimensions round-trip exactly.
    let decoded = image::load_from_memory(&pieces[0].data).unwrap();
    assert_eq!((decoded.width(), decoded.height()), (4, 4));
}

#[test]
fn split_yields_n_plus_one_pieces() {
    let img = decode_page("split-b"); // 8x8
    let mut p = rust_core::batch_edit::MultiEditParams::neutral();
    p.split = true;
    p.cut_lines = vec![0.5];
    p.horizontal_lines = true;

    let (pieces, ok) = rust_core::batch_edit::apply_edit_to_image(&img, &p, "png");
    assert!(ok);
    assert_eq!(pieces.len(), 2);
    // Horizontal cut → two stacked halves of the full width.
    let d0 = image::load_from_memory(&pieces[0].data).unwrap();
    assert_eq!((d0.width(), d0.height()), (8, 4));
}

#[test]
fn gif_and_tiff_map_to_png_output() {
    let img = decode_page("mapext");
    for weird in ["gif", "tiff", "tif"] {
        let mut p = rust_core::batch_edit::MultiEditParams::neutral();
        p.resize = true;
        p.percent = 50;
        let (pieces, ok) = rust_core::batch_edit::apply_edit_to_image(&img, &p, weird);
        assert!(ok, "apply succeeds for {}", weird);
        assert_eq!(pieces[0].ext, "png", "{} maps to png", weird);
    }
}

#[test]
fn jpeg_output_ext_is_preserved() {
    // A genuine RGB page — JPEG encode needs colour channels (not Luma).
    let mut buf = image::RgbImage::new(8, 8);
    for y in 0..8u32 {
        for x in 0..8u32 {
            buf.put_pixel(x, y, image::Rgb([(x * 30) as u8, (y * 30) as u8, ((x + y) * 20) as u8]));
        }
    }
    let img = DynamicImage::from(buf);
    let (pieces, ok) = rust_core::batch_edit::apply_edit_to_image(&img, &rust_core::batch_edit::MultiEditParams::neutral(), "jpg");
    assert!(ok);
    assert_eq!(pieces[0].ext, "jpg");
}

#[test]
fn decode_prefers_data_stream_over_archive_entry() {
    // A page whose edited Data stream is present decodes from that data.
    let png = make_png(6, 6, 42);
    let input = rust_core::batch_edit::MultiEditPageInput {
        idx: 0,
        orig_name: String::new(),
        data: Some(png.clone()),
        ext: "png".to_string(),
    };
    assert!(rust_core::batch_edit::decode_page_input(&input).is_some());

    // No Data stream and no archive path → undecodable (returns None for now).
    let empty = rust_core::batch_edit::MultiEditPageInput {
        idx: 1,
        orig_name: "page_0002.png".to_string(),
        data: None,
        ext: "png".to_string(),
    };
    assert!(rust_core::batch_edit::decode_page_input(&empty).is_none());
}

fn make_inputs(count: usize) -> Vec<rust_core::batch_edit::MultiEditPageInput> {
    (0..count)
        .map(|i| rust_core::batch_edit::MultiEditPageInput {
            idx: i,
            orig_name: String::new(),
            data: Some(make_png(16, 16, ((i % 7) as u8) + 1)),
            ext: "png".to_string(),
        })
        .collect()
}

#[test]
fn parallel_run_matches_sequential_reference_and_preserves_indices() {
    let inputs = make_inputs(24);

    let mut params = rust_core::batch_edit::MultiEditParams::neutral();
    params.resize = true;
    params.percent = 75;
    params.split = true;
    params.cut_lines = vec![0.33, 0.66]; // three pieces each

    let parallel = rust_core::batch_edit::apply_batch_to_inputs(&inputs, &params);

    assert_eq!(parallel.len(), inputs.len());

    // Results stay in input order (index is authoritative even with a rayon
    // worker pool), and each page's bytes match an explicit single-threaded run.
    for (pos, result) in parallel.iter().enumerate() {
        assert_eq!(result.idx, pos);

        let reference = rust_core::batch_edit::decode_page_input(&inputs[pos]).map(|img| {
            rust_core::batch_edit::apply_edit_to_image(&img, &params, "png").0
        });
        match reference {
            Some(ref_pieces) => {
                assert_eq!(result.pieces.len(), ref_pieces.len());
                for (got, want) in result.pieces.iter().zip(ref_pieces.iter()) {
                    assert_eq!(got.data, want.data);
                    assert_eq!(got.ext, want.ext);
                }
            }
            None => panic!("input {} should decode deterministically", pos),
        }
    }

    // Byte-identical regardless of how often / in which order the pool runs.
    let again = rust_core::batch_edit::apply_batch_to_inputs(&inputs, &params);
    assert_eq!(again.len(), parallel.len());
    for (a, b) in parallel.iter().zip(again.iter()) {
        assert_eq!(a.idx, b.idx);
        assert_eq!(a.pieces.len(), b.pieces.len());
        for (x, y) in a.pieces.iter().zip(b.pieces.iter()) {
            assert_eq!(x.data, y.data);
            assert_eq!(x.ext, y.ext);
        }
    }
}

#[test]
fn parallel_run_reports_failed_pages_as_empty_pieces() {
    let inputs = vec![
        rust_core::batch_edit::MultiEditPageInput {
            idx: 0,
            orig_name: String::new(),
            data: Some(make_png(16, 16, 9)),
            ext: "png".to_string(),
        },
        rust_core::batch_edit::MultiEditPageInput {
            idx: 1,
            orig_name: "page_0002.png".to_string(), // no data stream → undecodable
            data: None,
            ext: "png".to_string(),
        },
    ];
    let params = rust_core::batch_edit::MultiEditParams::neutral();

    let results = rust_core::batch_edit::apply_batch_to_inputs(&inputs, &params);
    assert_eq!(results.len(), 2);
    assert_eq!(results[0].idx, 0);
    assert_eq!(results[1].idx, 1);
    assert_eq!(results[0].pieces.len(), 1, "decodable page yields a piece");
    assert!(results[1].pieces.is_empty(), "undecodable page yields none");
}

#[test]
fn parallel_run_is_neutral_noop() {
    let inputs = make_inputs(8);
    let results = rust_core::batch_edit::apply_batch_to_inputs(&inputs, &rust_core::batch_edit::MultiEditParams::neutral());
    assert_eq!(results.len(), 8);
    for r in &results {
        assert_eq!(r.pieces.len(), 1);
        assert_eq!(r.pieces[0].ext, "png");
    }
}
