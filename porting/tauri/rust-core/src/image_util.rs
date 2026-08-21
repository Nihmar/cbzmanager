/// Image utilities: magic-byte detection, decode/encode/scale, center-anchor
/// scroll math. Replaces `uimgutil.pas` + `uwebp.pas`.
///
/// All functions operate on raw bytes and DynamicImage — no widgetset / GUI
/// dependencies. Safe to call from background threads.

use std::path::Path;

use image::{self, codecs::jpeg::JpegEncoder, DynamicImage, ExtendedColorType, GenericImageView, ImageEncoder};

use crate::helpers::base64_encode;

// ---------------------------------------------------------------------------
// Magic-byte format detection (same as Pascal DetectImageFormat)
// ---------------------------------------------------------------------------

/// Detected image format.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ImageFormat {
    Jpeg,
    Png,
    Webp,
    Bmp,
    Gif,
    Tiff,
}

/// Magic-byte signatures (first bytes of each format).
const JPEG_MAGIC: [u8; 3] = [0xFF, 0xD8, 0xFF];
const PNG_MAGIC: [u8; 4] = [0x89, 0x50, 0x4E, 0x47];
const GIF_MAGIC: [u8; 4] = [0x47, 0x49, 0x46, 0x38];
const BMP_MAGIC: [u8; 2] = [0x42, 0x4D];
const WEBP_MAGIC: [u8; 12] = [
    0x52, 0x49, 0x46, 0x46, // "RIFF"
    0x00, 0x00, 0x00, 0x00, // file size (don't care)
    0x57, 0x45, 0x42, 0x50, // "WEBP"
];
const TIFF_LE_MAGIC: [u8; 4] = [0x49, 0x49, 0x2A, 0x00]; // little-endian
const TIFF_BE_MAGIC: [u8; 4] = [0x4D, 0x4D, 0x00, 0x2A]; // big-endian

/// Detect image format from the first bytes of raw data.
///
/// Returns None if the format cannot be determined or the buffer is too short.
pub fn detect_format(bytes: &[u8]) -> Option<ImageFormat> {
    if bytes.len() < 4 {
        return None;
    }

    // JPEG: FF D8 FF
    if bytes[0] == JPEG_MAGIC[0] && bytes[1] == JPEG_MAGIC[1] && bytes[2] == JPEG_MAGIC[2] {
        return Some(ImageFormat::Jpeg);
    }

    // PNG: 89 50 4E 47
    if bytes[0] == PNG_MAGIC[0]
        && bytes[1] == PNG_MAGIC[1]
        && bytes[2] == PNG_MAGIC[2]
        && bytes[3] == PNG_MAGIC[3]
    {
        return Some(ImageFormat::Png);
    }

    // GIF: 47 49 46 38
    if bytes[0] == GIF_MAGIC[0]
        && bytes[1] == GIF_MAGIC[1]
        && bytes[2] == GIF_MAGIC[2]
        && bytes[3] == GIF_MAGIC[3]
    {
        return Some(ImageFormat::Gif);
    }

    // BMP: 42 4D
    if bytes[0] == BMP_MAGIC[0] && bytes[1] == BMP_MAGIC[1] {
        return Some(ImageFormat::Bmp);
    }

    // WebP: RIFF....WEBP (at least 12 bytes)
    if bytes[0] == WEBP_MAGIC[0]
        && bytes[1] == WEBP_MAGIC[1]
        && bytes[2] == WEBP_MAGIC[2]
        && bytes[3] == WEBP_MAGIC[3]
        && bytes[8] == WEBP_MAGIC[8]
        && bytes[9] == WEBP_MAGIC[9]
        && bytes[10] == WEBP_MAGIC[10]
        && bytes[11] == WEBP_MAGIC[11]
    {
        return Some(ImageFormat::Webp);
    }

    // TIFF: 49 49 2A 00 (LE) or 4D 4D 00 2A (BE)
    if (bytes[0] == TIFF_LE_MAGIC[0] && bytes[1] == TIFF_LE_MAGIC[1] && bytes[2] == TIFF_LE_MAGIC[2] && bytes[3] == TIFF_LE_MAGIC[3])
        || (bytes[0] == TIFF_BE_MAGIC[0] && bytes[1] == TIFF_BE_MAGIC[1] && bytes[2] == TIFF_BE_MAGIC[2] && bytes[3] == TIFF_BE_MAGIC[3])
    {
        return Some(ImageFormat::Tiff);
    }

    None
}

/// Detect image format from a file path (reads first 12 bytes).
pub fn detect_format_from_path(path: &Path) -> Option<ImageFormat> {
    if let Ok(data) = std::fs::read(path) {
        detect_format(&data)
    } else {
        None
    }
}

/// Get the output extension for a detected format.
pub fn ext_for(fmt: ImageFormat) -> &'static str {
    match fmt {
        ImageFormat::Jpeg => "jpg",
        ImageFormat::Png => "png",
        ImageFormat::Webp => "webp",
        ImageFormat::Bmp => "bmp",
        ImageFormat::Gif => "png",     // no GIF encoder — map to PNG (same as Pascal EncodeExtFor)
        ImageFormat::Tiff => "png",    // no TIFF encoder — map to PNG
    }
}

// ---------------------------------------------------------------------------
// Decode / encode
// ---------------------------------------------------------------------------

/// JPEG re-encode quality (high enough that repeated edit/save cycles don't
/// visibly degrade comic pages). Same as DEFAULT_JPEG_QUALITY = 92.
const DEFAULT_JPEG_QUALITY: u8 = 92;

/// WebP conversion quality. Matches Pascal convert-webp default of 75%.
pub const WEBP_QUALITY: u32 = 75;

/// Decode raw bytes into a DynamicImage.
///
/// Uses the `image` crate which supports JPEG, PNG, BMP, GIF, TIFF, and WebP.
pub fn decode_image(bytes: &[u8]) -> Result<DynamicImage> {
    image::load_from_memory(bytes).map_err(|e| Error::Decode(e.to_string()))
}

/// Encode a DynamicImage back to raw bytes in the target format.
///
/// - JPEG: quality 92 (DEFAULT_JPEG_QUALITY) unless overridden (1-100)
/// - WebP: default quality 75 via image crate's built-in encoder
/// - PNG/BMP: lossless (quality ignored)
/// - GIF/TIFF: encoded as PNG (same mapping as Pascal EncodeExtFor)
pub fn encode_image(img: &DynamicImage, format: ImageFormat, quality: u32) -> Result<Vec<u8>> {
    let buffer = img.to_rgba8();

    match format {
        ImageFormat::Jpeg => {
            // JPEG has no alpha channel — encode from the RGB buffer with an
            // Rgb8 color type (Rgba8 is rejected by the encoder).
            let rgb = img.to_rgb8();
            let q = if quality > 0 { quality as u8 } else { DEFAULT_JPEG_QUALITY };
            let mut buf: Vec<u8> = Vec::new();
            JpegEncoder::new_with_quality(&mut buf, q).write_image(
                rgb.as_raw(),
                img.width(),
                img.height(),
                ExtendedColorType::Rgb8,
            ).map_err(|e| Error::Encode(e.to_string()))?;
            Ok(buf)
        }
        ImageFormat::Png => {
            let mut buf: Vec<u8> = Vec::new();
            buffer.write_to(&mut std::io::Cursor::new(&mut buf), image::ImageFormat::Png)
                .map_err(|e| Error::Encode(e.to_string()))?;
            Ok(buf)
        }
        ImageFormat::Webp => {
            let mut buf: Vec<u8> = Vec::new();
            buffer.write_to(&mut std::io::Cursor::new(&mut buf), image::ImageFormat::WebP)
                .map_err(|e| Error::Encode(e.to_string()))?;
            Ok(buf)
        }
        ImageFormat::Bmp => {
            let mut buf: Vec<u8> = Vec::new();
            buffer.write_to(&mut std::io::Cursor::new(&mut buf), image::ImageFormat::Bmp)
                .map_err(|e| Error::Encode(e.to_string()))?;
            Ok(buf)
        }
        ImageFormat::Gif | ImageFormat::Tiff => {
            // GIF/TIFF → PNG (same mapping as Pascal EncodeExtFor).
            let mut buf: Vec<u8> = Vec::new();
            buffer.write_to(&mut std::io::Cursor::new(&mut buf), image::ImageFormat::Png)
                .map_err(|e| Error::Encode(e.to_string()))?;
            Ok(buf)
        }
    }
}

/// Encode to JPEG at default quality (92). Convenience wrapper.
pub fn encode_jpeg(img: &DynamicImage) -> Result<Vec<u8>> {
    encode_image(img, ImageFormat::Jpeg, 0)
}

/// Encode to PNG (lossless). Convenience wrapper.
pub fn encode_png(img: &DynamicImage) -> Result<Vec<u8>> {
    encode_image(img, ImageFormat::Png, 0)
}

/// Encode to WebP at default quality (75 via image crate's built-in encoder).
pub fn encode_webp_default(img: &DynamicImage) -> Result<Vec<u8>> {
    encode_image(img, ImageFormat::Webp, 0)
}

/// Convert raw image bytes to WebP. Attempts to decode first, then encodes as WebP.
/// Returns the WebP data if successful, otherwise returns the original data.
pub fn convert_bytes_to_webp(data: &[u8], quality: u32) -> Result<Vec<u8>> {
    let img = decode_image(data)?;
    encode_image(&img, ImageFormat::Webp, quality * 256 / 100) // image crate uses 0-255 for quality
}

// ---------------------------------------------------------------------------
// Scale / resample
// ---------------------------------------------------------------------------

/// Scale an image to fit within `max_width × max_height` while preserving
/// aspect ratio. Never enlarges (scale factor capped at 1.0).
///
/// Uses a box filter — same algorithm as Pascal's ScaleIntfImage box-filter
/// path for BGRA32 data.
pub fn scale_image(img: &DynamicImage, max_width: u32, max_height: u32) -> DynamicImage {
    if max_width == 0 || max_height == 0 {
        return img.clone();
    }

    let (w, h) = img.dimensions();
    if w == 0 || h == 0 {
        return img.clone();
    }

    // Scale factor: the smaller ratio, never > 1.0.
    let scale_x = max_width as f64 / w as f64;
    let scale_y = max_height as f64 / h as f64;
    let scale = scale_x.min(scale_y).min(1.0);

    if scale >= 1.0 {
        return img.clone();
    }

    let new_w = (w as f64 * scale).max(1.0) as u32;
    let new_h = (h as f64 * scale).max(1.0) as u32;

    // Triangle (linear) filter for resize — closest approximation to Pascal's
    // box-filter in the image crate 0.25 (Box was removed in favor of Triangle).
    img.resize_exact(new_w, new_h, image::imageops::FilterType::Triangle)
}

// ---------------------------------------------------------------------------
// Center-anchor scroll math (same algorithm as Pascal CenterAnchorScrollPos)
// ---------------------------------------------------------------------------

/// Compute the scroll position that keeps a content point centered under the
/// viewport after zooming from `old_zoom` to `new_zoom`.
///
/// Matches Pascal's `CenterAnchorScrollPos`:
/// ```text
/// Result := Round(ACenter * ANewZoom / AOldZoom) - AArea div 2;
/// clamped to [0, AContent - AArea].
/// ```
pub fn center_anchor(
    center: f64,
    old_zoom: f64,
    new_zoom: f64,
    content_size: f64,
    view_size: f64,
) -> f64 {
    if content_size <= view_size || old_zoom <= 0.0 || new_zoom <= 0.0 {
        return 0.0;
    }

    let max_pos = content_size - view_size;
    let result = (center * new_zoom / old_zoom) - (view_size / 2.0);
    result.max(0.0).min(max_pos)
}

// ---------------------------------------------------------------------------
// Thumbnail generation (frontend-facing: base64-encoded JPEG)
// ---------------------------------------------------------------------------

/// Default thumbnail cache width used in the main form and sequence builder.
pub const THUMB_CACHE_WIDTH: u32 = 320;

/// Generate a thumbnail from raw image bytes, returned as a base64-encoded
/// JPEG data URL (e.g. "data:image/jpeg;base64,...").
///
/// Pipeline: decode → scale to cache_width → JPEG encode at q92 → base64.
pub fn generate_thumbnail(bytes: &[u8], cache_width: u32) -> Result<String> {
    let img = decode_image(bytes)?;
    let thumb_width = if cache_width > 0 { cache_width } else { THUMB_CACHE_WIDTH };

    // Compute thumbnail height using the same aspect ratio as Pascal.
    let _thumb_height = (thumb_width as f64 * 1.25) as u32; // PAGE_ASPECT_RATIO = 1.25
    let thumb = scale_image(&img, thumb_width, u32::MAX);

    let jpeg_data = encode_jpeg(&thumb)?;
    Ok(base64_encode(&jpeg_data))
}

/// Generate a thumbnail as raw JPEG bytes (for Tauri IPC where base64 is
/// applied by the caller). Returns None if decoding/scaling fails.
pub fn generate_thumbnail_raw(bytes: &[u8], cache_width: u32) -> Option<Vec<u8>> {
    let img = decode_image(bytes).ok()?;
    let thumb_width = if cache_width > 0 { cache_width } else { THUMB_CACHE_WIDTH };
    let _thumb_height = (thumb_width as f64 * 1.25) as u32;
    let thumb = scale_image(&img, thumb_width, u32::MAX);
    encode_jpeg(&thumb).ok()
}

// ---------------------------------------------------------------------------
// Error types
// ---------------------------------------------------------------------------

/// Errors that can occur during image operations.
#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("Decode error: {0}")]
    Decode(String),

    #[error("Encode error: {0}")]
    Encode(String),
}

/// Result type for image operations.
pub type Result<T> = std::result::Result<T, Error>;
