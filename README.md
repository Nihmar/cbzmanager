# cbzmanager

A FreePascal / Lazarus GUI application for managing CBZ (Comic Book ZIP) files.

Port in progress — the reference Python CLI implementation lives in `porting/cbz_manager/`.

> **Scope note:** `find-similar`, `delete-pages-by-id`, and the batch `delete-pages`
> operation are **out of scope** and will not be ported. The in-place page editor
> (Gone flag + stage bar) in the preview pane covers the single-file delete/renumber
> use case that matters for interactive use.

## Dependencies

### libwebp (optional, required for WebP thumbnails)

Many CBZ files store their pages as WebP. Decoding them requires **libwebp**, which
is loaded dynamically at runtime — it is *not* needed to build the project.

If the library is missing the application still runs: CBZ files using JPEG, PNG, BMP
or GIF work normally, while WebP-only archives simply show no thumbnail. The startup
log (`cbzmanager.log`, written next to the executable) records which library was
loaded, or reports `libwebp NON trovata` when none was found.

The loader accepts any of `libwebp.so.7`, `libwebp.so.6`, `libwebp.so`,
`libwebpdecoder.so*` on Linux, `libwebp.dylib` / `libwebpdecoder.dylib` on macOS, and
`libwebp.dll`, `webp.dll`, `libwebp-7.dll` or `libwebpdecoder.dll` on Windows. Only
the decoder entry points `WebPGetInfo` and `WebPDecodeBGRA` are required; `WebPFree`
is used when present.

#### Linux

Install the distribution package — the library then resolves from the system path
with no further setup:

```bash
sudo apt install libwebp7        # Debian / Ubuntu
```

```bash
sudo dnf install libwebp         # Fedora / RHEL
```

```bash
sudo pacman -S libwebp           # Arch
```

#### macOS

```bash
brew install webp
```

#### Windows

Google's official libwebp release archives ship static libraries and command line
tools only, so they contain no usable DLL. Obtain `libwebp.dll` from a build that
distributes shared libraries (for example [vcpkg](https://vcpkg.io) with
`vcpkg install libwebp:x64-windows`) and copy it **next to `cbzmanager.exe`**,
together with its companion `libsharpyuv.dll` when the build provides one:

```
bin\debug\x86_64-win64\
    cbzmanager.exe
    libwebp.dll
    libsharpyuv.dll
```

Placing the DLLs beside the executable matters: the directory containing the running
`.exe` is the first location Windows searches, both for the library itself and for
its dependencies. A `libwebp.dll` left elsewhere and referenced by absolute path
fails to load its own dependencies.

The DLL architecture must match the build target. A 64-bit `libwebp.dll` is ignored
by a 32-bit (`i386-win32`) build, and vice versa.

## Planned operations

| Operation | Status |
|-----------|--------|
| **validate** — Verify CBZ files are valid ZIP archives with non-corrupted images (supports `.webp`) | ✅ Ported |
| **convert-webp** — Convert images to WebP (quality 75%) only if smaller; filter `ComicInfo.xml`; rename to `page_NNNN.*`; backup or delete | ✅ Ported |
| **merge** — Merge chapter CBZ files (`Title - NNNN.cbz`) into volumes (`Title VNNN.cbz`); auto-calculate CPV | ✅ Ported |
| **delete-pages** — Delete pages by 1-indexed position; renumber survivors | ❌ Out of scope (in-place editor covers single-file case) |
| **find-similar** — Find similar pages using 64-bit difference hashing; extract groups | ❌ Out of scope |
| **delete-pages-by-id** — Delete entries by `filename.cbz:entry_name.ext` ID | ❌ Out of scope |

All operations filter out `ComicInfo.xml` and rename remaining images to `page_NNNN.*`.

## Reference

The Python CLI in `porting/cbz_manager/` is the reference implementation with full tests.
