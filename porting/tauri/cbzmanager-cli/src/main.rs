// cbzmanager CLI — headless mode matching Pascal `uclimode.pas`.
//
// Subcommands: validate, convert-webp, merge, cbr-to-cbz
// Exit codes: 0 = success/no-op, 1 = runtime error, 2 = usage error

use std::path::PathBuf;
use std::process;

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use tracing_subscriber::EnvFilter;

#[derive(Parser)]
#[command(name = "cbzmanager", version = "0.1.0", about = "CBZ comic archive manager (headless mode)")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Verify CBZ files are valid and images readable
    Validate {
        /// Directory containing CBZ files
        dir: PathBuf,
        /// Decode pages on N worker threads (default: auto)
        #[arg(long, value_name = "N")]
        threads: Option<usize>,
    },

    /// Convert images to WebP (quality 75%, only if smaller)
    ConvertWebp {
        /// Directory containing CBZ files
        dir: PathBuf,
        /// Delete originals after conversion (default: rename to _OLD.cbz)
        #[arg(long)]
        delete: bool,
        /// WebP quality (0..=100; 0 = default q75). Larger archives are still dropped unless smaller.
        #[arg(long)]
        quality: Option<u32>,
        /// Decode/encode pages on N worker threads (default: auto)
        #[arg(long, value_name = "N")]
        threads: Option<usize>,
    },

    /// Merge chapter CBZ files into volumes
    Merge {
        /// Directory containing chapter/volume CBZs
        dir: PathBuf,
        /// Delete originals after processing (default: rename to _OLD.cbz)
        #[arg(long)]
        delete: bool,
        /// Append remaining chapters to the last volume
        #[arg(long)]
        force: bool,
        /// Exact chapter counts per volume (comma-separated, e.g. 5,5,5)
        #[arg(long, value_name = "N1,N2,...")]
        chapters: Option<String>,
        /// Fixed chapters per volume
        #[arg(long, value_name = "N")]
        chapters_per_volume: Option<usize>,
    },

    /// Convert CBR (RAR) archives to CBZ
    CbrToCbz {
        /// Directory containing CBR files
        dir: PathBuf,
        /// Delete the .cbr source after conversion (default: keep)
        #[arg(long)]
        delete: bool,
        /// Convert files on N worker threads (default: auto, max 4)
        #[arg(long, value_name = "N")]
        threads: Option<usize>,
    },
}

fn parse_chapters_list(s: &str) -> Result<Vec<usize>> {
    let mut result = Vec::new();
    for part in s.split(',') {
        let trimmed = part.trim();
        if trimmed.is_empty() {
            return Err(anyhow::anyhow!("empty element in --chapters list"));
        }
        let val: usize = trimmed.parse().context("non-numeric value in --chapters")?;
        if val == 0 {
            return Err(anyhow::anyhow!("--chapters values must be positive"));
        }
        result.push(val);
    }
    if result.is_empty() {
        return Err(anyhow::anyhow!("--chapters list is empty"));
    }
    Ok(result)
}

fn resolve_threads(value: Option<usize>, default: usize, cap: usize) -> usize {
    match value {
        Some(0) | None => default.min(cap),
        Some(n) if n > cap => cap,
        Some(n) => n,
    }
}

fn run() -> Result<i32> {
    let cli = Cli::parse();

    match cli.command {
        Command::Validate { dir, threads } => cmd_validate(&dir, threads),
        Command::ConvertWebp {
            dir,
            delete,
            quality,
            threads,
        } => cmd_convert_webp(&dir, delete, threads, quality),
        Command::Merge {
            dir,
            delete,
            force,
            chapters,
            chapters_per_volume,
        } => cmd_merge(&dir, delete, force, chapters, chapters_per_volume),
        Command::CbrToCbz { dir, delete, threads } => cmd_cbr_to_cbz(&dir, delete, threads),
    }
}

fn cmd_validate(dir: &PathBuf, threads_opt: Option<usize>) -> Result<i32> {
    let dir = dir.canonicalize().context("invalid directory")?;
    if !dir.is_dir() {
        return Err(anyhow::anyhow!("'{}' is not a valid directory", dir.display()));
    }

    let files = rust_core::helpers::collect_cbz_files(&dir);
    if files.is_empty() {
        println!("No .cbz files found in {}", dir.display());
        return Ok(0);
    }

    let threads = resolve_threads(threads_opt, rust_core::helpers::online_cpu_count(), rust_core::types::MAX_WEBP_THREADS);

    println!("Checking {} CBZ file(s)...", files.len());

    let results = rust_core::validate::validate_deep(&dir, &files, threads);

    let mut fail_count = 0usize;
    for r in &results {
        if r.valid {
            println!("  OK   {} ({} image(s))", r.file_name, r.image_count);
        } else {
            fail_count += 1;
            println!("  FAIL {}: {}", r.file_name, r.error_msg);
        }
    }

    let valid = results.len() - fail_count;
    println!("Valid: {}  Invalid: {}  Total: {}", valid, fail_count, results.len());

    if fail_count > 0 {
        Ok(1)
    } else {
        Ok(0)
    }
}

fn cmd_convert_webp(dir: &PathBuf, delete: bool, threads_opt: Option<usize>, quality_opt: Option<u32>) -> Result<i32> {
    let dir = dir.canonicalize().context("invalid directory")?;
    if !dir.is_dir() {
        return Err(anyhow::anyhow!("'{}' is not a valid directory", dir.display()));
    }

    let files = rust_core::helpers::collect_cbz_files(&dir);
    if files.is_empty() {
        println!("No .cbz files found in {}", dir.display());
        return Ok(0);
    }

    println!("Found {} CBZ file(s)", files.len());

    let threads = resolve_threads(threads_opt, rust_core::helpers::online_cpu_count(), rust_core::types::MAX_WEBP_THREADS);

    // 0 = use the server default (q75); values >100 are clamped by the encoder.
    let quality = quality_opt.unwrap_or(0);

    let results = rust_core::convert_webp::convert_webp(&dir, &files, threads, delete, quality);

    let mut converted = 0usize;
    let mut skipped = 0usize;
    for r in &results {
        if r.converted {
            converted += 1;
            println!("  {}: {} → .webp ({} bytes saved)", r.file_name, r.original_size - r.new_size, r.original_size);
        } else {
            skipped += 1;
            if !r.error_msg.is_empty() {
                println!("  -: {}: {}", r.file_name, r.error_msg);
            }
        }
    }
    println!("Summary: Converted: {}  Skipped: {}", converted, skipped);

    Ok(0)
}

fn cmd_merge(
    dir: &PathBuf,
    delete: bool,
    force: bool,
    chapters_str: Option<String>,
    chapters_per_volume_opt: Option<usize>,
) -> Result<i32> {
    // --chapters and --chapters-per-volume are mutually exclusive.
    if chapters_str.is_some() && chapters_per_volume_opt.is_some() {
        eprintln!("Error: --chapters and --chapters-per-volume are mutually exclusive");
        return Ok(2);
    }

    let dir = dir.canonicalize().context("invalid directory")?;
    if !dir.is_dir() {
        return Err(anyhow::anyhow!("'{}' is not a valid directory", dir.display()));
    }

    // Parse chapters list if provided.
    let chapters_list: Option<Vec<usize>> = match chapters_str {
        Some(ref s) => Some(parse_chapters_list(s)?),
        None => None,
    };

    let results = rust_core::merge::merge_chapters(&dir, delete, force, chapters_list, chapters_per_volume_opt);

    if results.is_empty() {
        println!("No chapter files found (pattern: 'Title - NNNN.cbz' or 'Title - SP01.cbz')");
        return Ok(0);
    }

    let mut failed = false;
    for r in &results {
        if !r.error_msg.is_empty() {
            if r.error_msg.contains("No chapter files found") {
                println!("{}", r.error_msg);
            } else {
                eprintln!("{}: {}", r.series_name, r.error_msg);
                failed = true;
            }
        } else if r.volumes_created > 0 {
            println!(
                "{}: {} volume(s) created",
                r.series_name, r.volumes_created
            );
        }
    }

    if failed {
        Ok(1)
    } else {
        Ok(0)
    }
}

fn cmd_cbr_to_cbz(dir: &PathBuf, _delete: bool, threads_opt: Option<usize>) -> Result<i32> {
    let dir = dir.canonicalize().context("invalid directory")?;
    if !dir.is_dir() {
        return Err(anyhow::anyhow!("'{}' is not a valid directory", dir.display()));
    }

    // Check CBR reader availability at runtime.
    if !rust_core::cbr_reader::cbr_supported() {
        eprintln!("Error: CBR support requires libarchive (libarchive.so / archive.dll)");
        return Ok(1);
    }

    let files = rust_core::cbr_convert::collect_cbr_files(&dir);
    if files.is_empty() {
        println!("No .cbr files found in {}", dir.display());
        return Ok(0);
    }

    let file_paths: Vec<PathBuf> = files.iter().map(|f| dir.join(f)).collect();
    println!("Found {} CBR file(s)", file_paths.len());

    let threads = resolve_threads(threads_opt, rust_core::helpers::online_cpu_count(), rust_core::types::MAX_CBR_THREADS);

    let results = rust_core::cbr_convert::convert_cbr_to_cbz(&dir, &file_paths, threads, false);

    let mut converted = 0usize;
    let mut skipped = 0usize;
    for r in &results {
        if r.converted {
            converted += 1;
            println!("  {}: {} page(s) -> .cbz", r.file_name, r.original_size);
        } else {
            skipped += 1;
            if !r.error_msg.is_empty() {
                println!("  -: {}: {}", r.file_name, r.error_msg);
            }
        }
    }
    println!("Summary: Converted: {}  Skipped: {}", converted, skipped);

    Ok(0)
}

fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")))
        .init();

    let exit_code = match run() {
        Ok(code) => code,
        Err(e) => {
            eprintln!("Error: {}", e);
            1
        }
    };

    process::exit(exit_code);
}
