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

/// Handle to a loaded libarchive instance.
///
/// The `Library` is intentionally retained here for the lifetime of the
/// symbols (see [`try_load_libarchive`]): dropping it would call `dlclose` and
/// unload `libarchive.so`, leaving every cached function pointer dangling.
#[derive(Debug)]
pub struct ArchiveHandle {
    #[allow(dead_code)]
    handle: libloading::Library,
}

#[repr(C)]
#[derive(Debug)]
struct Archive {
    _private: [u8; 0],
}

type ArchiveReadNewFn = unsafe extern "C" fn() -> *mut Archive;
type ArchiveReadFreeFn = unsafe extern "C" fn(*mut Archive);
type ArchiveReadOpenFilenameFn = unsafe extern "C" fn(*mut Archive, *const c_char, usize) -> c_int;
type ArchiveReadNextHeaderFn = unsafe extern "C" fn(*mut Archive, *mut *mut c_void) -> c_int;
type ArchiveReadDataFn = unsafe extern "C" fn(*mut Archive, *mut c_void, usize) -> isize;
type ArchiveEntryPathnameFn = unsafe extern "C" fn(*mut c_void) -> *const c_char;
type ArchiveEntrySizeFn = unsafe extern "C" fn(*mut c_void) -> u64;
type ArchiveSupportFilterFn = unsafe extern "C" fn(*mut Archive);
type ArchiveSupportFormatZipFn = unsafe extern "C" fn(*mut Archive);

struct ArchiveSymbols {
    // Retained so libarchive.so stays mapped while the fn pointers below are in
    // use; dropping it would dlclose and dangle every cached pointer.
    #[allow(dead_code)]
    lib: libloading::Library,
    read_new: ArchiveReadNewFn,
    read_free: ArchiveReadFreeFn,
    read_open_filename: ArchiveReadOpenFilenameFn,
    read_next_header: ArchiveReadNextHeaderFn,
    read_data: ArchiveReadDataFn,
    entry_pathname: ArchiveEntryPathnameFn,
    entry_size: ArchiveEntrySizeFn,
    support_filter_all: ArchiveSupportFilterFn,
    support_format_zip: ArchiveSupportFormatZipFn,
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

/// Extract an owned (Copy) function pointer out of a borrowed `Symbol`.
///
/// `libloading::Symbol<'a>` borrows the `Library` for its whole lifetime, which
/// would prevent us from moving the `Library` into [`ArchiveSymbols`] while also
/// using the pointers. Deref-copied here so the borrow ends at each call. Panics
/// if the symbol is absent — a missing core libarchive entry point means this
/// build cannot drive the reader, so we fail loudly rather than dangle.
unsafe fn load_ptr<F: Copy>(handle: &libloading::Library, name: &[u8]) -> F {
    let sym: libloading::Symbol<F> = handle.get(name).expect("missing libarchive symbol");
    *sym
}

/// Try to load the libarchive symbols. Returns None if loading fails.
fn try_load_libarchive() -> Option<ArchiveSymbols> {
    let libs = ["libarchive.so", "libarchive.so.13", "libarchive.so.12"];

    for lib_name in &libs {
        match unsafe { libloading::Library::new(lib_name) } {
            Ok(handle) => {
                let read_new: ArchiveReadNewFn =
                    unsafe { load_ptr(&handle, b"archive_read_new") };
                let read_free: ArchiveReadFreeFn =
                    unsafe { load_ptr(&handle, b"archive_read_free") };
                let read_open_filename: ArchiveReadOpenFilenameFn =
                    unsafe { load_ptr(&handle, b"archive_read_open_filename") };
                let read_next_header: ArchiveReadNextHeaderFn =
                    unsafe { load_ptr(&handle, b"archive_read_next_header") };
                let read_data: ArchiveReadDataFn =
                    unsafe { load_ptr(&handle, b"archive_read_data") };
                let entry_pathname: ArchiveEntryPathnameFn =
                    unsafe { load_ptr(&handle, b"archive_entry_pathname") };
                let entry_size: ArchiveEntrySizeFn =
                    unsafe { load_ptr(&handle, b"archive_entry_size") };
                let support_filter_all: ArchiveSupportFilterFn =
                    unsafe { load_ptr(&handle, b"archive_read_support_filter_all") };
                let support_format_zip: ArchiveSupportFormatZipFn =
                    unsafe { load_ptr(&handle, b"archive_read_support_format_zip") };

                return Some(ArchiveSymbols {
                    lib: handle,
                    read_new,
                    read_free,
                    read_open_filename,
                    read_next_header,
                    read_data,
                    entry_pathname,
                    entry_size,
                    support_filter_all,
                    support_format_zip,
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
        // libarchive does not auto-register the ZIP reader; enable filters and
        // the zip format explicitly before opening.
        (symbols.support_filter_all)(archive_ptr);
        (symbols.support_format_zip)(archive_ptr);
        let rc = (symbols.read_open_filename)(archive_ptr, c_path.as_ptr(), 0);
        if rc != ARCHIVE_OK {
            (symbols.read_free)(archive_ptr);
            return Err(format!("Cannot open {}: archive error {}", file_path.display(), rc));
        }

        loop {
            let rc = (symbols.read_next_header)(archive_ptr, &mut entry_ptr);
            // ARCHIVE_OK is 0 on this build; a non-zero result marks end-of-archive.
            // Only dereference the entry while rc == OK so the pointer is valid.
            if rc != ARCHIVE_OK {
                break;
            }

            let pathname = CStr::from_ptr((symbols.entry_pathname)(entry_ptr));
            if let Ok(name) = pathname.to_str() {
                if is_cbr_image_ext(name) {
                    names.push(name.to_string());
                }
            }
        }

        (symbols.read_free)(archive_ptr);
    }

    Ok(names)
}

// Archive return codes. Matches the libarchive ABI on this build (see
// /usr/include/archive.h: `#define ARCHIVE_OK 0`): a successful open or header
// read returns OK (0); anything else from `read_open_filename`/`read_next_header`
// is treated as an error or end-of-archive.
const ARCHIVE_OK: c_int = 0;

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
        // libarchive does not auto-register the ZIP reader; enable filters and
        // the zip format explicitly before opening.
        (symbols.support_filter_all)(archive_ptr);
        (symbols.support_format_zip)(archive_ptr);
        let rc = (symbols.read_open_filename)(archive_ptr, c_path.as_ptr(), 0);
        if rc != ARCHIVE_OK {
            (symbols.read_free)(archive_ptr);
            return Err(format!("Cannot open {}: archive error {}", file_path.display(), rc));
        }

        loop {
            let rc = (symbols.read_next_header)(archive_ptr, &mut entry_ptr);
            // On this libarchive build `read_next_header` returns ARCHIVE_OK (0)
            // for each valid entry and a non-zero result at end-of-archive; treat
            // any non-OK as termination. Processing is gated on exactly OK so the
            // entry pointer is never dereferenced while stale or null.
            if rc != ARCHIVE_OK {
                break;
            }

            let pathname = CStr::from_ptr((symbols.entry_pathname)(entry_ptr));
            let Some(name) = pathname.to_str().ok() else {
                continue;
            };
            if !is_cbr_image_ext(name) || is_comicinfo_xml(name) || name.ends_with('/') {
                continue;
            }

            let size = (symbols.entry_size)(entry_ptr) as usize;
            let mut data: Vec<u8> = Vec::with_capacity(size);
            let mut total_read: usize = 0;
            while total_read < size {
                let to_read = std::cmp::min(buf.len(), size - total_read);
                let bytes_read = (symbols.read_data)(archive_ptr, buf.as_mut_ptr() as *mut c_void, to_read as usize);
                if bytes_read <= 0 {
                    break;
                }
                data.extend_from_slice(&buf[..bytes_read as usize]);
                total_read += bytes_read as usize;
            }

            entries.push((name.to_string(), data));
        }

        (symbols.read_free)(archive_ptr);
    }

    // Sort alphabetically (matching Pascal behavior).
    entries.sort_by(|a, b| a.0.to_lowercase().cmp(&b.0.to_lowercase()));
    Ok(entries)
}
