#!/usr/bin/env python3
"""
CBZ to WebP Converter with TUI

This script converts images inside CBZ (Comic Book ZIP) files to WebP format
to reduce file size while maintaining quality. Features include:
- Beautiful Terminal UI with real-time progress tracking
- Multi-threaded parallel processing for speed
- Smart conversion (only converts if WebP is smaller)
- Memory system to skip already-converted files
- Automatic backups of conversion history

Created: 2026
License: Free for personal use
"""

# Standard library imports
import argparse  # Command-line argument parsing
import json  # JSON file reading/writing for memory storage
import os  # File system operations
import shutil  # High-level file operations for backup
import sys  # System-specific parameters and functions
import time  # Time-related functions for delays

# Multi-threading for parallel processing
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime  # Timestamp generation for backups
from io import BytesIO  # In-memory binary streams for ZIP processing
from pathlib import Path  # Object-oriented filesystem paths
from threading import Lock  # Thread synchronization for shared resources

# ZIP file handling
from zipfile import ZIP_DEFLATED, ZIP_STORED, ZipFile

# Image processing
from PIL import Image  # Python Imaging Library for image conversion
from rich import box

# Rich library for beautiful terminal UI
from rich.console import Console
from rich.layout import Layout
from rich.live import Live
from rich.panel import Panel
from rich.progress import (
    BarColumn,
    Progress,
    SpinnerColumn,
    TaskProgressColumn,
    TextColumn,
    TimeRemainingColumn,
)
from rich.table import Table
from rich.text import Text

# Initialize Rich console for formatted output
console = Console()

# Global lock for thread-safe operations
# This prevents race conditions when multiple threads try to update shared state
progress_lock = Lock()

# CRITICAL: Global lock for memory file I/O operations
# This prevents multiple CBZ files from trying to save memory simultaneously
# Without this lock, concurrent writes can corrupt or partially overwrite the JSON file
memory_save_lock = Lock()

# Global state dictionary for current processing status
# Shared across threads and updated during processing
current_state = {
    "folder": "Waiting...",  # Current folder being processed
    "cbz": "Waiting...",  # Current CBZ file being processed
    "stats": {  # Running statistics
        "total_processed": 0,  # Number of CBZ files successfully processed
        "total_saved": 0,  # Total bytes saved (negative = size reduction)
        "images_converted": 0,  # Number of images converted to WebP
        "folders_processed": 0,  # Number of folders completed
        "folders_skipped": 0,  # Number of folders skipped (no files/already done)
        "files_skipped_cached": 0,  # Number of files skipped due to memory cache
    },
}


def backup_memory_file(memory_file):
    """
    Create a timestamped backup of the memory file before loading it.

    This protects against data loss by creating a snapshot of the conversion
    history before any modifications are made. Backups are named with the
    current date and time (e.g., conversion_memory_20260130_143052.json).

    Args:
        memory_file (Path): Path to the memory JSON file to backup

    Returns:
        Path: Path to the created backup file, or None if backup failed

    Note:
        Failures are non-fatal - the script will continue even if backup fails
    """
    if memory_file.exists():
        try:
            # Create timestamp in format: yyyymmdd_HHMMSS
            # This ensures chronological sorting and uniqueness
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

            # Create backup filename by inserting timestamp before extension
            # Example: conversion_memory.json -> conversion_memory_20260130_143052.json
            backup_file = (
                memory_file.parent
                / f"{memory_file.stem}_{timestamp}{memory_file.suffix}"
            )

            # Copy the file with metadata preservation (timestamps, permissions)
            shutil.copy2(memory_file, backup_file)

            return backup_file
        except IOError as e:
            # Non-fatal error - warn user but continue processing
            console.print(
                f"[yellow]Warning: Could not create backup of memory file: {e}[/yellow]"
            )
            return None
    return None  # File doesn't exist, nothing to backup


def load_conversion_memory(memory_file):
    """
    Load the conversion memory from JSON file.

    The memory file tracks which files have been converted to avoid
    redundant processing. It also supports a 'skip' flag per series
    to permanently ignore certain folders.

    Args:
        memory_file (Path): Path to the conversion_memory.json file

    Returns:
        dict: Memory dictionary with structure:
              {
                  "Series Name": {
                      "files": ["file1.cbz", "file2.cbz"],
                      "skip": false
                  }
              }
              Returns empty dict {} if file doesn't exist or is corrupted

    Note:
        Automatically adds 'skip': false to old memory files for backward compatibility
    """
    if memory_file.exists():
        try:
            # Read and parse JSON file
            with open(memory_file, "r", encoding="utf-8") as f:
                memory = json.load(f)

                # Ensure all series have the 'skip' property (backward compatibility)
                # Older versions of the script didn't include this property
                for series_name in memory:
                    if "skip" not in memory[series_name]:
                        memory[series_name]["skip"] = False
                return memory
        except (json.JSONDecodeError, IOError):
            # If file is corrupted or unreadable, start fresh
            # This prevents the script from crashing on malformed JSON
            return {}
    return {}  # File doesn't exist yet - first run


def save_conversion_memory(memory_file, memory):
    """
    Save the conversion memory to JSON file with atomic write.

    Called after each successful file conversion to persist progress.
    Uses atomic write pattern (write to temp, then rename) to prevent
    corruption if interrupted mid-write.

    CRITICAL: Uses global lock to prevent multiple concurrent writes
    which can cause data loss or corruption.

    Args:
        memory_file (Path): Path where to save conversion_memory.json
        memory (dict): Memory dictionary to save

    Note:
        Uses ensure_ascii=False to properly save Unicode characters in filenames
        Atomic writes ensure file is never in partially-written state
    """
    # CRITICAL: Acquire lock before any file operations
    # Multiple CBZ files finishing at the same time must wait in queue
    with memory_save_lock:
        try:
            # Write to temporary file first (atomic write pattern)
            temp_file = (
                memory_file.parent / f"{memory_file.stem}_temp{memory_file.suffix}"
            )

            with open(temp_file, "w", encoding="utf-8") as f:
                # indent=2 makes the JSON human-readable
                # ensure_ascii=False allows Unicode characters (e.g., Japanese titles)
                json.dump(memory, f, indent=2, ensure_ascii=False)
                f.flush()  # Ensure data is written to disk
                os.fsync(f.fileno())  # Force OS to write to disk (prevent buffer loss)

            # Atomic rename - ensures file is never corrupted
            # If process crashes during rename, we still have either old or new file
            if memory_file.exists():
                memory_file.unlink()  # Remove old file (Windows requires this)
            temp_file.rename(memory_file)  # Atomic on Unix, near-atomic on Windows

        except IOError as e:
            # Make errors VERY visible - this is critical data loss
            console.print(
                f"\n[bold red]⚠ ERROR: Could not save conversion memory![/bold red]"
            )
            console.print(f"[red]Reason: {e}[/red]")
            console.print(
                f"[yellow]Your conversion progress may not be saved![/yellow]"
            )
            console.print(f"[yellow]Check disk space and file permissions![/yellow]\n")
        except Exception as e:
            console.print(
                f"\n[bold red]⚠ UNEXPECTED ERROR saving memory: {e}[/bold red]\n"
            )


def is_file_converted(memory, series_name, file_name):
    """
    Check if a file has already been converted.

    Used to skip files that are already in the memory to avoid
    redundant processing on subsequent runs.

    Args:
        memory (dict): The conversion memory dictionary
        series_name (str): Name of the series (folder name)
        file_name (str): Name of the CBZ file

    Returns:
        bool: True if file exists in memory, False otherwise

    Example:
        >>> is_file_converted(memory, "Naruto", "Naruto_V001.cbz")
        True
    """
    if series_name in memory:
        # Use .get() with default [] to handle old memory files without 'files' key
        return file_name in memory[series_name].get("files", [])
    return False  # Series not in memory yet


def mark_file_converted(memory, series_name, file_name):
    """
    Mark a file as converted in memory (thread-safe).

    Adds the file to the conversion memory after successful processing.
    Creates the series entry if it doesn't exist.

    CRITICAL: Uses global lock to prevent race conditions when multiple
    threads try to modify the memory dictionary simultaneously.

    Args:
        memory (dict): The conversion memory dictionary (modified in-place)
        series_name (str): Name of the series (folder name)
        file_name (str): Name of the CBZ file that was converted

    Note:
        - Preserves existing 'skip' value if series already exists
        - Avoids duplicate entries in the files list
        - Memory is modified in-place and should be saved afterward
    """
    # Acquire lock to prevent concurrent modifications
    with memory_save_lock:
        if series_name not in memory:
            # Create new series entry with default values
            memory[series_name] = {"files": [], "skip": False}

        # Ensure skip property exists (for backward compatibility with old memory files)
        if "skip" not in memory[series_name]:
            memory[series_name]["skip"] = False

        # Add file to list if not already present (avoid duplicates)
        if file_name not in memory[series_name].get("files", []):
            memory[series_name]["files"].append(file_name)


def is_series_skipped(memory, series_name):
    """
    Check if a series is marked to be skipped.

    Users can manually edit conversion_memory.json and set "skip": true
    for series they want to permanently ignore.

    Args:
        memory (dict): The conversion memory dictionary
        series_name (str): Name of the series (folder name)

    Returns:
        bool: True if series should be skipped, False otherwise

    Use case:
        - Series already optimized manually
        - Series that don't compress well with WebP
        - Series user doesn't want to convert
    """
    if series_name in memory:
        # Default to False if 'skip' key doesn't exist (old memory files)
        return memory[series_name].get("skip", False)
    return False  # Series not in memory - don't skip


def create_header(args, folder_count):
    """Create the configuration header panel."""
    table = Table(show_header=False, box=None, padding=(0, 2))
    table.add_column(style="bold cyan", justify="right")
    table.add_column(style="white")
    table.add_column(style="bold cyan", justify="right")
    table.add_column(style="white")

    table.add_row("Folders:", str(folder_count), "Quality:", str(args.quality))
    table.add_row("Directory:", args.directory, "Threads:", str(args.threads))
    table.add_row(
        "Delete Originals:", "Yes" if args.delete else "No (rename to _OLD.cbz)", "", ""
    )

    return Panel(
        table,
        title="[bold green]CBZ to WebP Converter - Configuration",
        border_style="green",
        box=box.ROUNDED,
    )


def create_current_status():
    """Create the current status panel."""
    table = Table(show_header=False, box=None, padding=(0, 1))
    table.add_column(style="bold yellow", justify="right", width=20)
    table.add_column(style="white")

    table.add_row("Current Folder:", current_state["folder"])
    table.add_row("Current CBZ:", current_state["cbz"])

    return Panel(
        table,
        title="[bold blue]Current Processing",
        border_style="blue",
        box=box.ROUNDED,
    )


def create_stats_panel():
    """Create statistics panel."""
    stats = current_state["stats"]
    table = Table(show_header=False, box=None, padding=(0, 1))
    table.add_column(style="bold cyan", justify="right", width=20)
    table.add_column(style="white")

    table.add_row("Folders Processed:", f"{stats['folders_processed']}")
    table.add_row("CBZ Files Processed:", str(stats["total_processed"]))
    table.add_row("Files Skipped (cached):", str(stats["files_skipped_cached"]))
    table.add_row(
        "Total Space Saved:", f"{stats['total_saved'] / (1024 * 1024):.1f} MB"
    )
    table.add_row("Images Converted:", str(stats["images_converted"]))

    return Panel(
        table, title="[bold green]Statistics", border_style="green", box=box.ROUNDED
    )


def create_layout(args, folder_count):
    """Create the main layout."""
    layout = Layout()

    layout.split_column(
        Layout(name="header", size=7),
        Layout(name="status", size=5),
        Layout(name="stats", size=8),
        Layout(name="progress", size=12),
    )

    layout["header"].update(create_header(args, folder_count))
    layout["status"].update(create_current_status())
    layout["stats"].update(create_stats_panel())

    return layout


def is_image_file(filename):
    """Check if file is an image based on extension."""
    image_extensions = {".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".tif"}
    return Path(filename).suffix.lower() in image_extensions


def is_webp_file(filename):
    """Check if file is already a WebP image."""
    return Path(filename).suffix.lower() == ".webp"


def convert_image_to_webp(image_data, filename, quality=90):
    """
    Convert image data to WebP format.
    Returns WebP data if smaller, otherwise returns original data.
    """
    try:
        # Store original file size for comparison
        # We only want to use WebP if it actually saves space
        original_size = len(image_data)

        # Open image from raw bytes using PIL
        # BytesIO creates a file-like object from the byte data
        img = Image.open(BytesIO(image_data))

        # Handle different image color modes for WebP compatibility
        # RGBA = RGB with alpha (transparency) channel - keep as-is for WebP
        # LA = Luminance (grayscale) with alpha - keep as-is for WebP
        # Other modes need conversion to RGB for optimal WebP encoding
        if img.mode in ("RGBA", "LA"):
            # Keep alpha channel - WebP supports transparency
            pass
        elif img.mode != "RGB":
            # Convert other modes (P=palette, L=grayscale, etc.) to RGB
            # This ensures consistent WebP encoding
            img = img.convert("RGB")

        # Convert to WebP format in memory (no disk I/O)
        webp_buffer = BytesIO()
        # Parameters:
        # - format='WEBP': Output format
        # - quality=90: Compression quality (1-100, higher=better quality/larger file)
        # - method=6: Compression method (0-6, higher=slower but better compression)
        # - exif=b'': Strip EXIF metadata to save space
        img.save(webp_buffer, format="WEBP", quality=quality, method=6, exif=b"")
        webp_data = webp_buffer.getvalue()

        # Calculate the new size after WebP conversion
        webp_size = len(webp_data)

        # Only use WebP if it's actually smaller
        # This is critical for files that don't compress well (already optimized JPEGs, etc.)
        if webp_size < original_size:
            # WebP is smaller - use it!
            # Change file extension from .jpg/.png/etc to .webp
            new_filename = str(Path(filename).with_suffix(".webp"))
            return webp_data, new_filename, original_size, webp_size, True
        else:
            # WebP is larger or same size - keep original format
            # This prevents file size increases
            return image_data, filename, original_size, webp_size, False

    except Exception as e:
        # Image conversion failed (corrupted image, unsupported format, etc.)
        # Keep original image data to avoid data loss
        return image_data, filename, len(image_data), len(image_data), False


def process_single_file(filename, file_data, quality, image_progress, image_task):
    """
    Process a single file from the CBZ archive.

    This function is called by worker threads in parallel to convert images.
    It determines whether a file needs conversion and handles the conversion process.

    Args:
        filename (str): Name of the file within the CBZ archive
        file_data (bytes): Raw binary data of the file
        quality (int): WebP quality setting (1-100)
        image_progress (Progress): Rich progress bar object for image processing
        image_task: Task ID in the progress bar to update

    Returns:
        tuple: (new_filename, converted_data, original_size, new_size, was_converted)
    """
    result = None

    # Check if this is an image file that needs conversion
    # Skip already-WebP images and non-image files
    if is_image_file(filename) and not is_webp_file(filename):
        # This is a convertible image (JPG, PNG, etc.)
        # Convert it to WebP and get conversion results
        converted_data, new_filename, orig_size, new_size, converted = (
            convert_image_to_webp(file_data, filename, quality)
        )
        result = (new_filename, converted_data, orig_size, new_size, converted)
    else:
        # File is either:
        # - Already a WebP image (no need to reconvert)
        # - A non-image file (metadata, XML, etc.)
        # Keep it as-is without modification
        result = (filename, file_data, len(file_data), len(file_data), False)

    # Update the progress bar to show this file has been processed
    # Thread-safe: uses a lock to prevent race conditions
    with progress_lock:
        image_progress.update(image_task, advance=1)

    return result


def process_cbz_file(
    cbz_path,
    delete_original,
    quality,
    max_workers,
    folder_progress,
    cbz_progress,
    image_progress,
    folder_task,
    cbz_task,
    memory,
    series_name,
    memory_file,
):
    """
    Process a single CBZ file: convert images to WebP and recompress.

    This is the main processing function that:
    1. Reads the CBZ file into memory
    2. Spawns worker threads to convert images in parallel
    3. Recompresses everything into a new CBZ with maximum compression
    4. Handles the original file (delete or rename to _OLD)
    5. Updates the conversion memory

    Args:
        cbz_path (Path): Path to the CBZ file to process
        delete_original (bool): If True, delete original; if False, rename to _OLD
        quality (int): WebP quality setting (1-100)
        max_workers (int): Number of parallel worker threads
        folder_progress (Progress): Progress bar for folder-level tracking
        cbz_progress (Progress): Progress bar for CBZ file tracking
        image_progress (Progress): Progress bar for image-level tracking
        folder_task: Task ID for folder progress bar
        cbz_task: Task ID for CBZ progress bar
        memory (dict): Conversion memory dictionary (tracks converted files)
        series_name (str): Name of the series/folder being processed
        memory_file (Path): Path to save updated memory

    Returns:
        bool: True if successful, False if error occurred
    """
    cbz_name = cbz_path.name

    # Update global state to show which file we're currently processing
    # This is displayed in the TUI status panel
    with progress_lock:
        current_state["cbz"] = cbz_name

    try:
        # === PHASE 1: Load CBZ file into memory ===
        # Get original file size for before/after comparison
        original_file_size = os.path.getsize(cbz_path)

        # Read the entire CBZ (ZIP) file into RAM
        # This avoids disk I/O during processing for better performance
        with open(cbz_path, "rb") as f:
            cbz_data = BytesIO(f.read())

        # === PHASE 2: Extract all files from CBZ ===
        # CBZ files are just ZIP archives with images
        # We need to extract everything before processing
        files_to_process = []
        with ZipFile(cbz_data, "r") as zip_read:
            file_list = zip_read.namelist()  # Get list of all files in archive
            for filename in file_list:
                # Read each file into memory as raw bytes
                file_data = zip_read.read(filename)
                files_to_process.append((filename, file_data))

        # Create a progress task for tracking image conversion within this CBZ
        # This shows real-time progress of "Image X of Y" in the TUI
        image_task = image_progress.add_task(
            f"[cyan]Images", total=len(files_to_process)
        )

        # === PHASE 3: Process all files in parallel ===
        # Use ThreadPoolExecutor to convert multiple images simultaneously
        # This significantly speeds up processing on multi-core systems
        processed_files = {}  # Will store results: {original_filename: (new_filename, data)}
        total_orig_size = 0  # Track total original size of images
        total_new_size = 0  # Track total size after WebP conversion
        converted_count = 0  # Count how many images were actually converted to WebP

        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            # Submit all files to the thread pool for parallel processing
            # Each file gets processed by a worker thread
            future_to_filename = {
                executor.submit(
                    process_single_file,
                    filename,
                    file_data,
                    quality,
                    image_progress,
                    image_task,
                ): filename
                for filename, file_data in files_to_process
            }

            # Collect results as worker threads complete
            # as_completed returns futures as they finish (not in submission order)
            for future in as_completed(future_to_filename):
                filename = future_to_filename[future]
                try:
                    # Get result from worker thread
                    new_filename, converted_data, orig_size, new_size, was_converted = (
                        future.result()
                    )

                    # Store the processed file data
                    processed_files[filename] = (new_filename, converted_data)

                    # Accumulate statistics
                    total_orig_size += orig_size
                    total_new_size += new_size
                    if was_converted:
                        converted_count += 1  # Image was successfully converted to WebP

                except Exception as e:
                    # Worker thread encountered an error processing this file
                    # Keep the original file data to avoid data loss
                    for orig_filename, orig_data in files_to_process:
                        if orig_filename == filename:
                            processed_files[filename] = (filename, orig_data)
                            break

        # Remove the image progress task since all images are done
        image_progress.remove_task(image_task)

        # === PHASE 4: Create new CBZ with processed files ===
        # Write all processed files into a new ZIP archive
        new_cbz_data = BytesIO()
        with ZipFile(new_cbz_data, "w", ZIP_DEFLATED, compresslevel=9) as zip_write:
            # Write files in their original order (important for comic reading order)
            for original_filename, _ in files_to_process:
                if original_filename in processed_files:
                    new_filename, file_data = processed_files[original_filename]
                    # Use maximum ZIP compression (level 9) for smallest file size
                    zip_write.writestr(
                        new_filename,
                        file_data,
                        compress_type=ZIP_DEFLATED,
                        compresslevel=9,
                    )

        # === PHASE 5: Write new CBZ and handle original ===
        # Get the final compressed size
        new_cbz_data.seek(0)
        new_cbz_bytes = new_cbz_data.read()
        new_file_size = len(new_cbz_bytes)

        # --- PATCH: mark as processed as soon as new CBZ exists in memory ---
        mark_file_converted(memory, series_name, cbz_name)
        save_conversion_memory(memory_file, memory)

        # Calculate space savings (negative = saved space, positive = increased size)
        size_diff = new_file_size - original_file_size

        # Handle original file based on --delete flag
        if delete_original:
            # Delete mode: overwrite the original file with the new version
            with open(cbz_path, "wb") as f:
                f.write(new_cbz_bytes)
        else:
            # Backup mode: rename original to *_OLD.cbz, then write new file
            old_path = cbz_path.with_stem(cbz_path.stem + "_OLD")
            os.rename(cbz_path, old_path)  # Rename original
            with open(cbz_path, "wb") as f:
                f.write(new_cbz_bytes)  # Write new converted file

        # === PHASE 6: Update statistics and memory ===
        # Update global statistics (thread-safe with lock)
        with progress_lock:
            current_state["stats"]["total_processed"] += 1
            if size_diff < 0:  # Only count actual space savings
                current_state["stats"]["total_saved"] += abs(size_diff)
            current_state["stats"]["images_converted"] += converted_count

        # Mark this file as converted in memory so we can skip it next time
        mark_file_converted(memory, series_name, cbz_name)
        # Save memory immediately to disk (prevents data loss if script crashes)
        save_conversion_memory(memory_file, memory)

        # Verbose logging to confirm memory save
        # (Access args through a global or pass it as parameter - for now just save)

        # Update CBZ progress bar
        with progress_lock:
            cbz_progress.update(cbz_task, advance=1)

        return True  # Success!

    except Exception as e:
        # Fatal error processing this CBZ file
        # Update progress bar and continue to next file
        with progress_lock:
            cbz_progress.update(cbz_task, advance=1)
        return False  # Failure


def main():
    """
    Main entry point for the CBZ to WebP converter.

    This function orchestrates the entire conversion process:
    1. Parse command-line arguments
    2. Load folder list and conversion memory
    3. Set up the Terminal UI
    4. Process each folder and its CBZ files
    5. Display final statistics

    The function uses Rich's Live display for a real-time updating TUI
    that shows progress at three levels: folders, CBZ files, and images.
    """
    # === COMMAND-LINE ARGUMENT PARSING ===
    # Set up argument parser with description
    parser = argparse.ArgumentParser(
        description="Convert images in CBZ files to WebP format with TUI"
    )
    # Required positional argument: directory containing comic folders
    parser.add_argument(
        "directory", help="Directory containing the folders with CBZ files"
    )

    # Optional flag: delete originals instead of creating backups
    parser.add_argument(
        "--delete",
        action="store_true",
        help="Delete original CBZ files instead of renaming to _OLD.cbz",
    )

    # Optional parameter: WebP quality level (affects compression vs. image quality)
    parser.add_argument(
        "--quality",
        type=int,
        default=90,
        help="WebP quality level (1-100, default: 90)",
    )

    # Optional parameter: number of parallel processing threads
    parser.add_argument(
        "--threads",
        type=int,
        default=8,
        help="Number of parallel threads for image conversion (default: 8)",
    )

    # Optional flag: force re-conversion of all files (ignore memory)
    parser.add_argument(
        "--force",
        action="store_true",
        help="Force re-conversion of all files, ignoring conversion memory",
    )

    # Optional flag: verbose output for debugging
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable verbose output for debugging memory and file tracking",
    )

    # Parse the command-line arguments
    args = parser.parse_args()

    # === VALIDATE ARGUMENTS ===
    # Ensure quality is in valid range (1-100)
    if not 1 <= args.quality <= 100:
        console.print("[red]Error: Quality must be between 1 and 100[/red]")
        sys.exit(1)

    # Ensure thread count is reasonable (1-32)
    # Too many threads can cause excessive context switching
    if not 1 <= args.threads <= 32:
        console.print("[red]Error: Threads must be between 1 and 32[/red]")
        sys.exit(1)

    # === LOAD FOLDER LIST ===
    # Get the directory where the script is located
    # This is where to_convert.txt and conversion_memory.json are stored
    script_dir = Path(__file__).parent
    folder_list_file = script_dir / "to_convert.txt"

    # Validate that the target directory exists
    base_dir = Path(args.directory)

    if not base_dir.exists():
        console.print(f"[red]Error: Directory {args.directory} does not exist![/red]")
        sys.exit(1)

    # Try to read folder names from to_convert.txt
    # If file doesn't exist or is empty, we'll scan all folders in the directory
    folder_names = []
    if folder_list_file.exists():
        with open(folder_list_file, "r", encoding="utf-8") as f:
            # Read lines, strip whitespace, skip empty lines
            folder_names = [line.strip() for line in f if line.strip()]

    # If no folders specified, auto-discover all folders in target directory
    if not folder_names:
        # Get all subdirectories, but filter out:
        # - Hidden folders (starting with '.')
        # - System folders like .Trash-1000
        folder_names = [
            f.name
            for f in sorted(base_dir.iterdir())
            if f.is_dir() and not f.name.startswith(".") and f.name != ".Trash-1000"
        ]

        # Ensure we found at least one folder
        if not folder_names:
            console.print(f"[red]Error: No folders found in {args.directory}![/red]")
            sys.exit(1)

        # Inform user we're using auto-discovery mode
        console.print(
            f"[yellow]to_convert.txt not found or empty - processing all {len(folder_names)} folders in directory[/yellow]"
        )
    else:
        # Inform user how many folders were loaded from file
        console.print(
            f"[cyan]Loaded {len(folder_names)} folders from to_convert.txt[/cyan]"
        )

    # === LOAD CONVERSION MEMORY ===
    # The conversion memory tracks which files have already been converted
    # This prevents redundant processing when re-running the script
    memory_file = script_dir / "conversion_memory.json"

    # Create timestamped backup before loading (protects against data loss)
    backup_file = backup_memory_file(memory_file)
    if backup_file:
        console.print(f"[dim cyan]Backup created: {backup_file.name}[/dim cyan]")

    # Load the memory file (always load it, even with --force flag)
    # This ensures we preserve existing entries when saving
    conversion_memory = load_conversion_memory(memory_file)

    # Track whether we're forcing re-conversion
    # When True: process all files regardless of memory (but still save to memory)
    # When False: skip files that are already in memory
    force_reconvert = args.force

    # Display memory status to user
    if args.force and memory_file.exists():
        console.print(
            "[yellow]--force flag set: Will re-convert all files (memory preserved)[/yellow]"
        )
    elif memory_file.exists():
        # Calculate total files tracked in memory
        total_cached = sum(
            len(series.get("files", [])) for series in conversion_memory.values()
        )
        console.print(
            f"[cyan]Loaded conversion memory: {len(conversion_memory)} series, {total_cached} files already converted[/cyan]"
        )

        # Verbose mode: show detailed memory contents
        if args.verbose:
            console.print("\n[bold]Memory contents:[/bold]")
            for series_name, data in sorted(conversion_memory.items()):
                file_count = len(data.get("files", []))
                skip_status = " [red](SKIP)[/red]" if data.get("skip", False) else ""
                console.print(f"  • {series_name}: {file_count} files{skip_status}")
            console.print()

    # Create the layout
    layout = create_layout(args, len(folder_names))

    # Create progress bars
    folder_progress = Progress(
        TextColumn("[bold blue]{task.description}"),
        BarColumn(bar_width=None),
        TaskProgressColumn(),
        TimeRemainingColumn(),
        expand=True,
    )

    cbz_progress = Progress(
        TextColumn("[bold green]{task.description}"),
        BarColumn(bar_width=None),
        TaskProgressColumn(),
        expand=True,
    )

    image_progress = Progress(
        TextColumn("[bold yellow]{task.description}"),
        BarColumn(bar_width=None),
        TaskProgressColumn(),
        expand=True,
    )

    # Combine progress bars into a single panel
    progress_table = Table.grid(padding=(1, 2))
    progress_table.add_row(folder_progress)
    progress_table.add_row(cbz_progress)
    progress_table.add_row(image_progress)

    progress_panel = Panel(
        progress_table, title="[bold]Progress", border_style="cyan", box=box.ROUNDED
    )

    layout["progress"].update(progress_panel)

    # Start live display with reduced refresh rate
    with Live(layout, console=console, screen=False, refresh_per_second=4):
        # Create main folder task
        folder_task = folder_progress.add_task("Folders", total=len(folder_names))

        # === MAIN PROCESSING LOOP ===
        # Process each folder in the list
        for folder_name in folder_names:
            folder_path = base_dir / folder_name

            # Check if this series is marked to skip in the memory file
            # Users can manually set "skip": true in the JSON to ignore certain series
            if is_series_skipped(conversion_memory, folder_name):
                with progress_lock:
                    current_state["folder"] = folder_name
                    current_state["cbz"] = "Skipped (skip=true in memory)"
                    current_state["stats"]["folders_skipped"] += 1
                    folder_progress.update(folder_task, advance=1)
                layout["status"].update(create_current_status())
                layout["stats"].update(create_stats_panel())
                continue  # Skip to next folder

            # --- PATCH 4: ensure series exists in memory even if all files are skipped ---
            if folder_name not in conversion_memory:
                conversion_memory[folder_name] = {"files": [], "skip": False}
                save_conversion_memory(memory_file, conversion_memory)

            # Update TUI to show which folder we're currently processing
            with progress_lock:
                current_state["folder"] = folder_name
                current_state["cbz"] = "Scanning folder..."
            layout["status"].update(create_current_status())

            # Validate that the folder exists
            if not folder_path.exists():
                with progress_lock:
                    current_state["stats"]["folders_skipped"] += 1
                    folder_progress.update(folder_task, advance=1)
                    # Show why folder was skipped (helpful for debugging)
                    current_state["cbz"] = f"Folder not found: {folder_path}"
                    layout["stats"].update(create_stats_panel())
                    layout["status"].update(create_current_status())
                continue  # Skip to next folder

            # Validate that it's actually a directory (not a file)
            if not folder_path.is_dir():
                with progress_lock:
                    current_state["stats"]["folders_skipped"] += 1
                    folder_progress.update(folder_task, advance=1)
                    current_state["cbz"] = "Not a directory"
                    layout["stats"].update(create_stats_panel())
                    layout["status"].update(create_current_status())
                continue  # Skip to next folder

            # Find all CBZ files in this folder
            # CBZ files are comic book archives (just ZIP files with images)
            all_cbz_files = list(folder_path.glob("*.cbz"))
            # Filter out backup files (ending with _OLD from previous runs)
            cbz_files_no_old = [f for f in all_cbz_files if not f.stem.endswith("_OLD")]

            # Apply conversion memory filtering (unless --force flag is set)
            # This is the "smart skip" feature that avoids re-converting files
            if force_reconvert:
                # Force mode: process everything regardless of memory
                cbz_files = cbz_files_no_old
                if args.verbose:
                    console.print(
                        f"[dim]--force: Processing all {len(cbz_files)} files in {folder_name}[/dim]"
                    )
            else:
                # Normal mode: skip files that are already in the conversion memory
                if args.verbose:
                    console.print(
                        f"[dim]Checking memory for {folder_name}: {len(conversion_memory.get(folder_name, {}).get('files', []))} files in cache[/dim]"
                    )

                # cbz_files = [
                #     f
                #     for f in cbz_files_no_old
                #     if not is_file_converted(conversion_memory, folder_name, f.name)
                # ]

                cbz_files = []
                for f in cbz_files_no_old:
                    if is_file_converted(conversion_memory, folder_name, f.name):
                        continue

                    # PATCH: se il CBZ contiene già solo WebP → consideralo processato
                    try:
                        with ZipFile(f, "r") as z:
                            names = z.namelist()
                            if names and all(
                                Path(n).suffix.lower() == ".webp"
                                for n in names
                                if is_image_file(n)
                            ):
                                mark_file_converted(
                                    conversion_memory, folder_name, f.name
                                )
                                save_conversion_memory(memory_file, conversion_memory)
                                continue
                    except Exception:
                        pass

                    cbz_files.append(f)

                # Track how many files we skipped due to cache
                skipped_count = len(cbz_files_no_old) - len(cbz_files)
                if skipped_count > 0:
                    with progress_lock:
                        current_state["stats"]["files_skipped_cached"] += skipped_count
                    if args.verbose:
                        console.print(
                            f"[dim green]Skipped {skipped_count} cached files in {folder_name}[/dim green]"
                        )
                        for f in cbz_files_no_old:
                            if is_file_converted(
                                conversion_memory, folder_name, f.name
                            ):
                                console.print(f"[dim]  ✓ {f.name} (in cache)[/dim]")

                if args.verbose and len(cbz_files) > 0:
                    console.print(
                        f"[dim yellow]Will process {len(cbz_files)} files in {folder_name}:[/dim yellow]"
                    )
                    for f in cbz_files:
                        console.print(f"[dim]  → {f.name}[/dim]")

            if not cbz_files:
                with progress_lock:
                    current_state["stats"]["folders_skipped"] += 1
                    folder_progress.update(folder_task, advance=1)
                    if all_cbz_files:
                        if len(cbz_files_no_old) == 0:
                            current_state["cbz"] = (
                                f"Only _OLD files found ({len(all_cbz_files)})"
                            )
                        else:
                            current_state["cbz"] = (
                                f"All files already converted ({len(cbz_files_no_old)})"
                            )
                    else:
                        current_state["cbz"] = "No CBZ files found"
                    layout["stats"].update(create_stats_panel())
                    layout["status"].update(create_current_status())
                continue

            # Create CBZ progress task for this folder
            cbz_task = cbz_progress.add_task(
                f"CBZ files in {folder_name}", total=len(cbz_files)
            )

            # Process each CBZ file
            for idx, cbz_file in enumerate(cbz_files, 1):
                process_cbz_file(
                    cbz_file,
                    args.delete,
                    args.quality,
                    args.threads,
                    folder_progress,
                    cbz_progress,
                    image_progress,
                    folder_task,
                    cbz_task,
                    conversion_memory,
                    folder_name,
                    memory_file,
                )

                # Update stats display only every 3 files or on last file to reduce flickering
                if idx % 3 == 0 or idx == len(cbz_files):
                    layout["stats"].update(create_stats_panel())
                    layout["status"].update(create_current_status())

            # Remove CBZ task for this folder
            cbz_progress.remove_task(cbz_task)

            # Update folder progress and stats
            with progress_lock:
                current_state["stats"]["folders_processed"] += 1
                folder_progress.update(folder_task, advance=1)
            layout["stats"].update(create_stats_panel())
            layout["status"].update(create_current_status())

        # Mark as complete
        with progress_lock:
            current_state["folder"] = "Complete"
            current_state["cbz"] = "Complete"
        layout["status"].update(create_current_status())

    # Print final summary
    console.print("\n[bold green]✓ Conversion complete![/bold green]")
    stats = current_state["stats"]
    console.print(f"[cyan]Total CBZ files processed:[/cyan] {stats['total_processed']}")
    console.print(
        f"[cyan]Total space saved:[/cyan] {stats['total_saved'] / (1024 * 1024):.1f} MB"
    )
    console.print(f"[cyan]Total images converted:[/cyan] {stats['images_converted']}")


if __name__ == "__main__":
    main()
