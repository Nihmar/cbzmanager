//! Shared fixtures for rust-core integration tests.
//!
//! Builds deterministic in-memory PNG bytes and CBZ archives so tests do not
//! depend on external fixtures (mirrors the Python/`make` fixture generation).

#![allow(dead_code, unused_imports)]

use std::io::Cursor;
use std::path::Path;

use image::{GrayImage, ImageBuffer, Pixel, Rgb};

/// Build deterministic grey-gradient PNG bytes of `w` x `h`. Row `y` has grey
/// value `(y * 256 / h) as u8`; the seed perturbs columns so adjacent pages use
/// distinct byte content even with identical dimensions.
pub fn make_png(w: u32, h: u32, seed: u8) -> Vec<u8> {
    let mut img = ImageBuffer::new(w, h);
    for y in 0..h {
        for x in 0..w {
            let v = ((y as usize * 256 / h as usize) as u8).wrapping_add(seed);
            img.put_pixel(x, y, Rgb([v, v, v]));
        }
    }
    let mut buf = Vec::new();
    img.write_to(&mut Cursor::new(&mut buf), image::ImageFormat::Png)
        .expect("encode PNG");
    buf
}

/// Build deterministic *noise* PNG bytes of `w` x `h`. Noise compresses poorly in
/// lossless PNG but well in WebP, so conversion to WebP (when it happens) shrinks
/// the file — this exercises the real parallel encode path.
pub fn make_noise_png(w: u32, h: u32, seed: u64) -> Vec<u8> {
    let mut state = seed;
    let mut noise = image::GrayImage::new(w, h);
    for py in 0..h {
        for px in 0..w {
            // xorshift — cheap and deterministic.
            state ^= state << 13;
            state ^= state >> 7;
            state ^= state << 17;
            noise.put_pixel(px, py, image::Luma([(state % 256) as u8]));
        }
    }
    let mut buf = Vec::new();
    noise.write_to(&mut Cursor::new(&mut buf), image::ImageFormat::Png).unwrap();
    buf
}

/// Write a CBZ at `dir/name` from the given page byte-streams. ComicInfo.xml is
/// appended as the final entry so tests can assert it is present/filtered.
pub fn make_cbz(dir: &Path, name: &str, pages: &[Vec<u8>]) -> std::path::PathBuf {
    use rust_core::zip_ops::{write_zip_from_entries, ZipEntry};
    let path = dir.join(name);
    let mut entries: Vec<ZipEntry> = pages
        .iter()
        .enumerate()
        .map(|(i, p)| {
            ZipEntry::new(format!("page_{:04}.png", i + 1), p.clone())
        })
        .collect();
    entries.push(ZipEntry::new(
        "ComicInfo.xml",
        b"<ComicInfo><Title>Test</Title></ComicInfo>".to_vec(),
    ));
    write_zip_from_entries(&path, &entries).expect("write_cbz");
    path
}

/// Read every entry name out of a CBZ, in archive order.
pub fn cbz_names(path: &Path) -> Vec<String> {
    rust_core::zip_ops::get_entry_names(path).expect("read names")
}

/// Raw bytes of the named entry, or `None` when absent.
pub fn cbz_entry(path: &Path, name: &str) -> Option<Vec<u8>> {
    rust_core::zip_ops::read_entry(path, name).ok()
}
