/// CBR (RAR) reader via libarchive — dynamic loading.
///
/// Replaces `uarchive.pas` pattern: dynamically loads libarchive.so, provides
/// functions to iterate over image entries in a RAR archive and decode them
/// to images via uwebp.

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_void};
use std::path::Path;

use crate::helpers::is_comicinfo_xml;

// ---------------------------------------------------------------------------
// Dynamic libloading bindings
// ---------------------------------------------------------------------------

#[derive(Debug)]
pub struct ArchiveHandle {
    handle: libloading::Library,
}

#[repr(C)]
#[derive(Debug)]
struct Archive {
    _private: [u8; 0],
}

type archive_read_new_fn = unsafe extern "C" fn() -> *mut Archive;
type archive_read_free_fn = unsafe extern "C" fn(*mut Archive);
type archive_read_open_filename_fn = unsafe extern "C" fn(*mut Archive, *const c_char, usize) -> c_int;
type archive_read_next_header_fn = unsafe extern "C" fn(*mut Archive, *mut *mut c_void) -> c_int;
type archive_read_data_fn = unsafe extern "C" fn(*mut Archive, *mut c_void, usize) -> isize;
type archive_read_set_bytes_in_buffer_fn = unsafe extern "C" fn(*mut Archive, usize) -> c_int;
type archive_entry_pathname_fn = unsafe extern "C" fn(*mut c_void) -> *const c_char;
type archive_entry_size_fn = unsafe extern "C" fn(*mut c_void) -> u64;

struct ArchiveSymbols {
    read_new: archive_read_new_fn,
    read_free: archive_read_free_fn,
    read_open_filename: archive_read_open_filename_fn,
    read_next_header: archive_read_next_header_fn,
    read_data: archive_read_data_fn,
    set_bytes_in_buffer: archive_read_set_bytes_in_buffer_fn,
    entry_pathname: archive_entry_pathname_fn,
    entry_size: archive_entry_size_fn,
}

// ---------------------------------------------------------------------------
// Supported image extensions for CBR previews
// ---------------------------------------------------------------------------

const CBR_IMAGE_EXTS: &[&str] = &["jpg", "jpeg", "png", "webp", "bmp", "gif", "tiff", "tif"];

/// Check if a filename has a supported image extension.
pub fn is_cbr_image_ext(name: &str) -> bool {
    let ext = name.rsplit_once('.').map(|(_, e)| e.to_lowercase()).unwrap_or_default();
    CBR_IMAGE_EXTS.contains(&ext.as_str())
}

/// Try to load the libarchive symbols. Returns None if loading fails.
fn try_load_libarchive() -> Option<ArchiveSymbols> {
    let libs = ["libarchive.so", "libarchive.so.13", "libarchive.so.12"];

    for lib_name in &libs {
        match unsafe { libloading::Library::new(lib_name) } {
            Ok(handle) => {
                let read_new: libloading::Symbol<archive_read_new_fn> =
                    unsafe { handle.get(b"archive_read_new") }.ok()?;
                let read_free: libloading::Symbol<archive_read_free_fn> =
                    unsafe { handle.get(b"archive_read_free") }.ok()?;
                let read_open_filename: libloading::Symbol<archive_read_open_filename_fn> =
                    unsafe { handle.get(b"archive_read_open_filename") }.ok()?;
                let read_next_header: libloading::Symbol<archive_read_next_header_fn> =
                    unsafe { handle.get(b"archive_read_next_header") }.ok()?;
                let read_data: libloading::Symbol<archive_read_data_fn> =
                    unsafe { handle.get(b"archive_read_data") }.ok()?;
                let set_bytes_in_buffer: libloading::Symbol<archive_read_set_bytes_in_buffer_fn> =
                    unsafe { handle.get(b"archive_read_set_bytes_in_buffer") }.ok()?;
                let entry_pathname: libloading::Symbol<archive_entry_pathname_fn> =
                    unsafe { handle.get(b"archive_entry_pathname") }.ok()?;
                let entry_size: libloading::Symbol<archive_entry_size_fn> =
                    unsafe { handle.get(b"archive_entry_size") }.ok()?;

                return Some(ArchiveSymbols {
                    read_new: *read_new,
                    read_free: *read_free,
                    read_open_filename: *read_open_filename,
                    read_next_header: *read_next_header,
                    read_data: *read_data,
                    set_bytes_in_buffer: *set_bytes_in_buffer,
                    entry_pathname: *entry_pathname,
                    entry_size: *entry_size,
                });
            }
            Err(_) => continue,
        }
    }

    None
}

/// Check if CBR reading is supported (libarchive available).
pub fn cbr_supported() -> bool {
    try_load_libarchive().is_some()
}

/// Collect image entry names from a CBR file (scan phase 1: just names).
pub fn collect_cbr_image_names(file_path: &Path) -> Result<Vec<String>, String> {
    let symbols = try_load_libarchive()
        .ok_or_else(|| "libarchive not available — CBR reading requires libarchive.so".to_string())?;

    let c_path = CString::new(file_path.to_str().unwrap_or("")).map_err(|e| e.to_string())?;

    let archive_ptr: *mut Archive;
    unsafe {
        archive_ptr = (symbols.read_new)();
        if archive_ptr.is_null() {
            return Err("Failed to create archive handle".to_string());
        }
    }

    let mut names: Vec<String> = Vec::new();
    let mut entry_ptr: *mut c_void = std::ptr::null_mut();

    unsafe {
        let rc = (symbols.read_open_filename)(archive_ptr, c_path.as_ptr(), 0);
        if rc != ARCHIVE_OK {
            (symbols.read_free)(archive_ptr);
            return Err(format!("Cannot open {}: archive error {}", file_path.display(), rc));
        }

        loop {
            let rc = (symbols.read_next_header)(archive_ptr, &mut entry_ptr);
            if rc == ARCHIVE_EOF {
                break;
            }
            if rc < ARCHIVE_OK {
                continue;
            }

            if !entry_ptr.is_null() {
                let pathname = CStr::from_ptr((symbols.entry_pathname)(entry_ptr));
                if let Ok(name) = pathname.to_str() {
                    if is_cbr_image_ext(name) {
                        names.push(name.to_string());
                    }
                }
            }
        }

        (symbols.read_free)(archive_ptr);
    }

    Ok(names)
}

// Constants for archive return codes.
const ARCHIVE_OK: c_int = 1;
const ARCHIVE_EOF: c_int = -1;
const ARCHIVE_WARN: c_int = 2;

/// Read all image entries from a CBR file into memory.
pub fn collect_cbr_entries(file_path: &Path) -> Result<Vec<(String, Vec<u8>)>, String> {
    let symbols = try_load_libarchive()
        .ok_or_else(|| "libarchive not available — CBR reading requires libarchive.so".to_string())?;

    let c_path = CString::new(file_path.to_str().unwrap_or("")).map_err(|e| e.to_string())?;

    let archive_ptr: *mut Archive;
    unsafe {
        archive_ptr = (symbols.read_new)();
        if archive_ptr.is_null() {
            return Err("Failed to create archive handle".to_string());
        }
    }

    let mut entries: Vec<(String, Vec<u8>)> = Vec::new();
    let mut entry_ptr: *mut c_void = std::ptr::null_mut();
    let mut buf: [u8; 65536] = [0u8; 65536];

    unsafe {
        let rc = (symbols.read_open_filename)(archive_ptr, c_path.as_ptr(), 0);
        if rc != ARCHIVE_OK {
            (symbols.read_free)(archive_ptr);
            return Err(format!("Cannot open {}: archive error {}", file_path.display(), rc));
        }

        loop {
            let rc = (symbols.read_next_header)(archive_ptr, &mut entry_ptr);
            if rc == ARCHIVE_EOF {
                break;
            }
            if rc < ARCHIVE_OK {
                continue;
            }

            if !entry_ptr.is_null() {
                let pathname = CStr::from_ptr((symbols.entry_pathname)(entry_ptr));
                if let Ok(name) = pathname.to_str() {
                    if !is_cbr_image_ext(name) {
                        continue;
                    }
                    // Skip directories and ComicInfo.xml.
                    if is_comicinfo_xml(name) || name.ends_with('/') {
                        continue;
                    }

                    let size = (symbols.entry_size)(entry_ptr) as usize;
                    let mut data: Vec<u8> = Vec::with_capacity(size);
                    let mut bytes_read: isize = 0;
                    let mut total_read: usize = 0;

                    while total_read < size {
                        let to_read = std::cmp::min(buf.len(), size - total_read);
                        bytes_read = (symbols.read_data)(archive_ptr, buf.as_mut_ptr() as *mut c_void, to_read as usize);
                        if bytes_read <= 0 {
                            break;
                        }
                        data.extend_from_slice(&buf[..bytes_read as usize]);
                        total_read += bytes_read as usize;
                    }

                    entries.push((name.to_string(), data));
                }
            }
        }

        (symbols.read_free)(archive_ptr);
    }

    // Sort alphabetically (matching Pascal behavior).
    entries.sort_by(|a, b| a.0.to_lowercase().cmp(&b.0.to_lowercase()));
    Ok(entries)
}
