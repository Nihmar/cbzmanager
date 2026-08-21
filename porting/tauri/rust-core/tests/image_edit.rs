//! Image editing unit tests: resample, colour pipeline and split. Mirrors
//! `uimageedit.pas` — ResampleIntfImage, AdjustColors, SplitIntfImage.

mod common;

use image::DynamicImage;

use common::*;

fn decode(tag: &str) -> DynamicImage {
    let bytes = make_png(8, 8, tag.as_bytes()[0] % 200);
    image::load_from_memory(&bytes).expect("decode png")
}

#[test]
fn resample_downscales_and_upscales() {
    let img = decode("resamp");
    let down = rust_core::image_edit::resample_image(&img, 4, 4).expect("downscale");
    assert_eq!((down.width(), down.height()), (4, 4));

    let up = rust_core::image_edit::resample_image(&img, 16, 32).expect("upscale");
    assert_eq!((up.width(), up.height()), (16, 32));

    // A single degenerate dimension returns None.
    assert!(rust_core::image_edit::resample_image(&img, 0, 4).is_none());
}

#[test]
fn colour_identity_is_pixel_perfect() {
    let img = decode("identity");
    let out = rust_core::image_edit::adjust_colors(&img, &rust_core::image_edit::ColorAdjust::identity())
        .expect("identity returns image");
    assert_eq!(img.to_rgb8().as_raw(), out.to_rgb8().as_raw());

    assert!(
        rust_core::image_edit::ColorAdjust::identity().is_neutral(),
        "identity adjustment must report neutral"
    );
}

#[test]
fn colour_invert_flips_black_and_white() {
    let mut buf = image::RgbImage::new(2, 1);
    buf.put_pixel(0, 0, image::Rgb([0u8, 0, 0]));
    buf.put_pixel(1, 0, image::Rgb([255u8, 255, 255]));
    let img = DynamicImage::from(buf);

    let adj = rust_core::image_edit::ColorAdjust {
        invert: true,
        ..rust_core::image_edit::ColorAdjust::identity()
    };
    let out = rust_core::image_edit::adjust_colors(&img, &adj).unwrap().to_rgb8();

    assert_eq!(out.get_pixel(0, 0), &image::Rgb([255u8, 255, 255]));
    assert_eq!(out.get_pixel(1, 0), &image::Rgb([0u8, 0, 0]));
}

#[test]
fn colour_grayscale_matches_rec601_luma() {
    let mut buf = image::RgbImage::new(1, 1);
    buf.put_pixel(0, 0, image::Rgb([255u8, 0, 0])); // pure red
    let img = DynamicImage::from(buf);

    let adj = rust_core::image_edit::ColorAdjust {
        grayscale: true,
        ..rust_core::image_edit::ColorAdjust::identity()
    };
    let out = rust_core::image_edit::adjust_colors(&img, &adj).unwrap().to_rgb8();
    // 0.299 * 255 = 76.245 -> rounds to 76, applied to every channel.
    assert_eq!(out.get_pixel(0, 0), &image::Rgb([76u8, 76, 76]));
}

#[test]
fn colour_brightness_adds_offset() {
    let mut buf = image::RgbImage::new(1, 1);
    buf.put_pixel(0, 0, image::Rgb([100u8, 100, 100]));
    let img = DynamicImage::from(buf);

    let adj = rust_core::image_edit::ColorAdjust {
        brightness: 10.0,
        ..rust_core::image_edit::ColorAdjust::identity()
    };
    let out = rust_core::image_edit::adjust_colors(&img, &adj).unwrap().to_rgb8();
    assert_eq!(out.get_pixel(0, 0), &image::Rgb([110u8, 110, 110]));
}

#[test]
fn colour_pipeline_is_neutral_for_black_sepia() {
    // Black has zero contribution in the sepia matrix.
    let mut buf = image::RgbImage::new(1, 1);
    buf.put_pixel(0, 0, image::Rgb([0u8, 0, 0]));
    let img = DynamicImage::from(buf);

    let adj = rust_core::image_edit::ColorAdjust {
        sepia: true,
        ..rust_core::image_edit::ColorAdjust::identity()
    };
    let out = rust_core::image_edit::adjust_colors(&img, &adj).unwrap().to_rgb8();
    assert_eq!(out.get_pixel(0, 0), &image::Rgb([0u8, 0, 0]));
}

#[test]
fn vertical_cut_splits_into_plus_one_pieces() {
    let img = decode("split-v"); // 8x8
    let cuts = vec![rust_core::image_edit::CutLine {
        position: 0.5,
        horizontal: false,
    }];
    let pieces = rust_core::image_edit::split_image(&img, &cuts).expect("one cut");
    assert_eq!(pieces.len(), 2);
    // Two equal halves of the original height.
    assert_eq!((pieces[0].width(), pieces[0].height()), (4, 8));
    assert_eq!((pieces[1].width(), pieces[1].height()), (4, 8));
}

#[test]
fn multiple_cuts_yield_n_plus_one_pieces() {
    let img = decode("split-m"); // 9x9
    let cuts = vec![
        rust_core::image_edit::CutLine {
            position: 0.25,
            horizontal: true,
        },
        rust_core::image_edit::CutLine {
            position: 0.75,
            horizontal: true,
        },
    ];
    let pieces = rust_core::image_edit::split_image(&img, &cuts).expect("two cuts");
    assert_eq!(pieces.len(), 3);
}

#[test]
fn split_requires_at_least_one_cut() {
    let img = decode("split-none");
    assert!(rust_core::image_edit::split_image(&img, &[]).is_none());
}
