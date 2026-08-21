/// Image editing operations — resample, color adjust, split.
///
/// Replaces `uimageedit.pas`: `ResampleIntfImage` (box filter),
/// `AdjustColors` (fixed per-pixel pipeline), `SplitIntfImage` (parallel cut lines).
///
/// Uses the `image` crate for pixel-level manipulation instead of LCL's TLazIntfImage.

use image::DynamicImage;

// ---------------------------------------------------------------------------
// Resample — box filter resize
// ---------------------------------------------------------------------------

/// Resample an image to new dimensions using a box filter (nearest-neighbor quality).
/// Works for both enlargement and reduction.
///
/// Returns None for invalid input or output dimensions.
pub fn resample_image(img: &DynamicImage, new_w: u32, new_h: u32) -> Option<DynamicImage> {
    if img.width() == 0 || img.height() == 0 || new_w == 0 || new_h == 0 {
        return None;
    }

    // Use the image crate's resize_exact with Triangle filter.
    let resized = image::imageops::resize(img, new_w, new_h, image::imageops::FilterType::Triangle);
    Some(DynamicImage::from(resized))
}

// ---------------------------------------------------------------------------
// Color adjustment pipeline
// ---------------------------------------------------------------------------

/// Color adjustment parameters — mirrors Pascal `TColorAdjust`.
#[derive(Debug, Clone)]
pub struct ColorAdjust {
    pub invert: bool,
    pub grayscale: bool,
    pub sepia: bool,
    pub r_gain: f64,
    pub g_gain: f64,
    pub b_gain: f64,
    pub saturation: f64,
    pub contrast: f64,
    pub brightness: f64,
    pub gamma: f64,
}

impl Default for ColorAdjust {
    fn default() -> Self {
        Self::identity()
    }
}

impl ColorAdjust {
    /// Create an identity (neutral) adjustment.
    pub fn identity() -> Self {
        Self {
            invert: false,
            grayscale: false,
            sepia: false,
            r_gain: 1.0,
            g_gain: 1.0,
            b_gain: 1.0,
            saturation: 1.0,
            contrast: 1.0,
            brightness: 0.0,
            gamma: 1.0,
        }
    }

    /// Check if this adjustment is neutral (no effect).
    pub fn is_neutral(&self) -> bool {
        !self.invert && !self.grayscale && !self.sepia
            && self.r_gain == 1.0 && self.g_gain == 1.0 && self.b_gain == 1.0
            && self.saturation == 1.0 && self.contrast == 1.0
            && self.brightness == 0.0 && self.gamma == 1.0
    }

    /// Apply the adjustment pipeline to a single pixel (R, G, B in 0..255).
    fn transform_pixel(&self, r: f64, g: f64, b: f64) -> (f64, f64, f64) {
        let mut rr = r;
        let mut gg = g;
        let mut bb = b;

        // 1. Invert
        if self.invert {
            rr = 255.0 - rr;
            gg = 255.0 - gg;
            bb = 255.0 - bb;
        }

        // 2. Grayscale (Rec.601 luma)
        if self.grayscale {
            let l = 0.299 * rr + 0.587 * gg + 0.114 * bb;
            rr = l;
            gg = l;
            bb = l;
        }

        // 3. Sepia (standard matrix — uses original R/G/B)
        if self.sepia {
            let orig_r = r;
            let orig_g = g;
            let orig_b = b;
            rr = 0.393 * orig_r + 0.769 * orig_g + 0.189 * orig_b;
            gg = 0.349 * orig_r + 0.686 * orig_g + 0.168 * orig_b;
            bb = 0.272 * orig_r + 0.534 * orig_g + 0.131 * orig_b;
        }

        // 4. Per-channel gains
        rr *= self.r_gain;
        gg *= self.g_gain;
        bb *= self.b_gain;

        // 5. Saturation (mix toward Rec.601 luma)
        if self.saturation != 1.0 {
            let l = 0.299 * rr + 0.587 * gg + 0.114 * bb;
            rr = l + (rr - l) * self.saturation;
            gg = l + (gg - l) * self.saturation;
            bb = l + (bb - l) * self.saturation;
        }

        // 6. Contrast (factor around 128 midpoint)
        if self.contrast != 1.0 {
            rr = (rr - 128.0) * self.contrast + 128.0;
            gg = (gg - 128.0) * self.contrast + 128.0;
            bb = (bb - 128.0) * self.contrast + 128.0;
        }

        // 7. Brightness (additive offset)
        if self.brightness != 0.0 {
            rr += self.brightness;
            gg += self.brightness;
            bb += self.brightness;
        }

        // 8. Gamma
        if self.gamma != 1.0 {
            rr = 255.0 * f64::powf(rr / 255.0, 1.0 / self.gamma);
            gg = 255.0 * f64::powf(gg / 255.0, 1.0 / self.gamma);
            bb = 255.0 * f64::powf(bb / 255.0, 1.0 / self.gamma);
        }

        // Clamp to 0..255
        let rr = rr.max(0.0).min(255.0);
        let gg = gg.max(0.0).min(255.0);
        let bb = bb.max(0.0).min(255.0);

        (rr, gg, bb)
    }
}

/// Apply color adjustments to an image.
///
/// Returns None for invalid input.
pub fn adjust_colors(img: &DynamicImage, adj: &ColorAdjust) -> Option<DynamicImage> {
    if img.width() == 0 || img.height() == 0 {
        return None;
    }

    let mut buf = img.to_rgba8();

    for pixel in buf.pixels_mut() {
        let (r, g, b) = adj.transform_pixel(
            pixel[0] as f64,
            pixel[1] as f64,
            pixel[2] as f64,
        );
        pixel[0] = r.round() as u8;
        pixel[1] = g.round() as u8;
        pixel[2] = b.round() as u8;
        // Alpha preserved from source.
    }

    Some(DynamicImage::from(buf))
}

// ---------------------------------------------------------------------------
// Split
// ---------------------------------------------------------------------------

/// Represents a horizontal or vertical cut line in normalized 0..1 coordinates.
#[derive(Debug, Clone)]
pub struct CutLine {
    pub position: f64, // Normalized position in 0..1
    pub horizontal: bool, // True = horizontal line (cuts vertically)
}

/// Split an image along N parallel cut lines into N+1 pieces.
///
/// Pieces are returned in reading order (top-to-bottom for horizontal lines,
/// left-to-right for vertical lines).
pub fn split_image(img: &DynamicImage, cut_lines: &[CutLine]) -> Option<Vec<DynamicImage>> {
    if img.width() == 0 || img.height() == 0 || cut_lines.is_empty() {
        return None;
    }

    let horizontal = cut_lines[0].horizontal;
    let dim = if horizontal { img.height() } else { img.width() };

    // Sort and normalize cut positions.
    let mut sorted_cuts: Vec<u32> = cut_lines.iter().map(|cl| {
        let pos = (cl.position * dim as f64).round() as u32;
        pos.max(1).min(dim - 1)
    }).collect();

    // Sort ascending and remove duplicates.
    sorted_cuts.sort();
    sorted_cuts.dedup();

    if sorted_cuts.is_empty() {
        return None;
    }

    let mut pieces: Vec<DynamicImage> = Vec::new();

    if horizontal {
        // Horizontal cut lines → vertical strips (top to bottom).
        let mut start_y: u32 = 0;
        for &cut_y in &sorted_cuts {
            let piece_h = cut_y - start_y;
            if piece_h > 0 {
                let cropped = image::imageops::crop_imm(img, 0, start_y, img.width(), piece_h).to_image();
                pieces.push(DynamicImage::from(cropped));
            }
            start_y = cut_y;
        }
        // Last piece.
        let remaining_h = dim - start_y;
        if remaining_h > 0 {
            let cropped = image::imageops::crop_imm(img, 0, start_y, img.width(), remaining_h).to_image();
            pieces.push(DynamicImage::from(cropped));
        }
    } else {
        // Vertical cut lines → horizontal strips (left to right).
        let mut start_x: u32 = 0;
        for &cut_x in &sorted_cuts {
            let piece_w = cut_x - start_x;
            if piece_w > 0 {
                let cropped = image::imageops::crop_imm(img, start_x, 0, piece_w, img.height()).to_image();
                pieces.push(DynamicImage::from(cropped));
            }
            start_x = cut_x;
        }
        // Last piece.
        let remaining_w = dim - start_x;
        if remaining_w > 0 {
            let cropped = image::imageops::crop_imm(img, start_x, 0, remaining_w, img.height()).to_image();
            pieces.push(DynamicImage::from(cropped));
        }
    }

    if pieces.is_empty() {
        None
    } else {
        Some(pieces)
    }
}
