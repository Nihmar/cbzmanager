/// Validation service — quick and deep checks for CBZ archives.
///
/// Replaces `uservicevalidate.pas`:
///   - Validate()     : quick check (ZIP readable + image count > 0)
///   - ValidateDeep() : full decode test with per-image pass/fail

use rayon::iter::{IntoParallelRefIterator, ParallelIterator};

use crate::helpers::*;
use crate::image_util;
use crate::zip_ops;

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

/// Per-image validation result from a deep scan.
#[derive(Debug, Clone)]
pub struct ImageCheck {
    pub filename: String,
    pub ok: bool,
    pub errors: Vec<String>,
    pub depth: usize,
}

/// Per-file validation result.
#[derive(Debug, Clone)]
pub struct FileValidationResult {
    pub file_name: String,
    pub valid: bool,
    pub image_count: usize,
    pub error_msg: String,
    /// Populated only by `validate_deep`.
    pub image_checks: Vec<ImageCheck>,
}

/// Results for a batch of files.
pub type FileValidationResults = Vec<FileValidationResult>;

// ---------------------------------------------------------------------------
// Quick validation
// ---------------------------------------------------------------------------

/// Validate that each file is a readable CBZ with at least one image.
///
/// Calls `zip_ops::count_image_entries` to check if the archive has any
/// recognisable image extensions.
pub fn validate(dir: &std::path::Path, files: &[&str]) -> FileValidationResults {
    files
        .iter()
        .map(|&name| {
            let full_path = cbz_full_path(dir, name);
            let mut result = FileValidationResult {
                file_name: name.to_string(),
                valid: false,
                image_count: 0,
                error_msg: String::new(),
                image_checks: Vec::new(),
            };

            match zip_ops::count_image_entries(&full_path) {
                Ok(count) if count > 0 => {
                    result.valid = true;
                    result.image_count = count;
                }
                Ok(_) => {
                    result.error_msg = "No readable images found".to_string();
                }
                Err(e) => {
                    result.error_msg = e.to_string();
                }
            }

            result
        })
        .collect()
}

// ---------------------------------------------------------------------------
// Deep validation
// ---------------------------------------------------------------------------

/// Image extensions recognised by the app.
const IMAGE_EXTS: &[&str] = &["jpg", "jpeg", "png", "webp", "bmp", "gif", "tiff", "tif"];

/// Try to determine whether an entry name has a recognisable image extension.
fn is_image_ext(name: &str) -> bool {
    name.rsplit_once('.')
        .map(|(_, ext)| IMAGE_EXTS.contains(&ext.to_lowercase().as_str()))
        .unwrap_or(false)
}

/// Attempt to decode every image entry in a single CBZ.
///
/// Returns (successful_count, per_image_checks). Uses `rayon` for parallel
/// decode when `threads > 1`; sequential otherwise.
fn validate_one_deep(path: &std::path::Path, threads: usize) -> Result<(usize, Vec<ImageCheck>), zip_ops::Error> {
    let entries = zip_ops::collect_zip_entries(path)?;

    // Collect image entry names and their data.
    let mut image_data: Vec<(String, Vec<u8>)> = Vec::new();
    for entry in &entries {
        if is_image_ext(&entry.name) {
            image_data.push((entry.name.clone(), entry.data.clone()));
        }
    }

    if image_data.is_empty() {
        return Ok((0, Vec::new()));
    }

    let checks: Vec<ImageCheck> = if threads > 1 {
        // Parallel decode with rayon.
        image_data.par_iter().map(|(name, data)| {
            match image_util::decode_image(data) {
                Ok(_img) => ImageCheck {
                    filename: name.clone(),
                    ok: true,
                    errors: Vec::new(),
                    depth: 0,
                },
                Err(e) => ImageCheck {
                    filename: name.clone(),
                    ok: false,
                    errors: vec![e.to_string()],
                    depth: 0,
                },
            }
        }).collect()
    } else {
        // Sequential decode.
        image_data.iter().map(|(name, data)| {
            match image_util::decode_image(data) {
                Ok(_img) => ImageCheck {
                    filename: name.clone(),
                    ok: true,
                    errors: Vec::new(),
                    depth: 0,
                },
                Err(e) => ImageCheck {
                    filename: name.clone(),
                    ok: false,
                    errors: vec![e.to_string()],
                    depth: 0,
                },
            }
        }).collect()
    };

    let total_valid = checks.iter().filter(|c| c.ok).count();
    Ok((total_valid, checks))
}

/// Deep validate: decode every image and report per-image errors.
pub fn validate_deep(
    dir: &std::path::Path,
    files: &[&str],
    threads: usize,
) -> FileValidationResults {
    let progress = None; // CLI mode — no progress callback needed for validation service

    files
        .iter()
        .enumerate()
        .map(|(i, &name)| {
            let full_path = cbz_full_path(dir, name);
            report_service_progress(progress, "Validating", name, i, files.len());

            let mut result = FileValidationResult {
                file_name: name.to_string(),
                valid: false,
                image_count: 0,
                error_msg: String::new(),
                image_checks: Vec::new(),
            };

            match validate_one_deep(&full_path, threads) {
                Ok((total_valid, checks)) => {
                    result.image_checks = checks;
                    result.image_count = total_valid;
                    result.valid = total_valid > 0;

                    if total_valid == 0 && result.image_checks.is_empty() {
                        result.error_msg = "No images found".to_string();
                    } else if total_valid == 0 {
                        result.error_msg = "All images failed to decode".to_string();
                    } else if result.image_checks.iter().any(|c| !c.ok) {
                        result.error_msg = format!(
                            "{}/{} images valid",
                            total_valid,
                            result.image_checks.len()
                        );
                    }
                }
                Err(e) => {
                    result.valid = false;
                    result.image_count = 0;
                    result.error_msg = e.to_string();
                }
            }

            result
        })
        .collect()
}
