<p align="center">
  <img src="pkg/cbzmanager.svg" alt="cbzmanager" width="128">
</p>

# cbzmanager

A FreePascal / Lazarus desktop application for managing CBZ (Comic Book ZIP) files.

## Features

- **Validate** — verify CBZ archives are valid ZIPs with non-corrupted images (JPEG, PNG, BMP, GIF, WebP)
- **Convert to WebP** — re-encode images as WebP (configurable quality), keeping originals only when smaller; rename to `page_NNNN.*`; optional `_OLD.cbz` backup
- **Convert CBR to CBZ** — batch-convert RAR comic archives to CBZ entirely in RAM (via libarchive, loaded dynamically); read-only .cbr previews in the main window
- **Merge chapters** — combine chapter files (`Title - NNNN.cbz`) into volumes (`Title VNNN.cbz`) with auto-calculated chapters-per-volume
- **In-place page editor** — delete, reorder, sort, reverse, and renumber pages inside a single CBZ with live preview, stage bar (save/revert), and optional backup toggle
- **Add image from internet** — search nine key-less image sources for a cover and stage it as the new first page. [MangaDex](https://mangadex.org) is the default and the only one indexing covers *per volume*; the rest cover free image pools ([Openverse](https://openverse.org), [Wikimedia Commons](https://commons.wikimedia.org)), book covers ([Open Library](https://openlibrary.org)) and public domain art (Art Institute of Chicago, Metropolitan Museum, Cleveland Museum of Art, Wellcome Collection, NASA). A paste-a-URL mode is also available. Nothing is written until you save via the stage bar
- **ComicInfo.xml** — view, edit, remove, or generate `ComicInfo.xml` metadata embedded in CBZ archives
- **Sequence builder** — define custom volume/chapter grouping sequences for non-standard merge layouts; resizable, with zoomable thumbnails and keyboard shortcuts
- **Job Monitor** — non-modal progress window showing real-time progress bar, current task, elapsed time, and scrolling log for all background operations

## Building

### Requirements

- [Lazarus IDE](https://www.lazarus-ide.org/) 2.2+ with Free Pascal Compiler 3.2+
- LCL package (included with Lazarus)

### From Lazarus IDE

Open `cbzmanager.lpi` and build. Two build modes are available:

| Mode | Output | Notes |
|------|--------|-------|
| **Debug** | `bin/debug/<cpu>-<os>/cbzmanager` | DWARF3 debug info, heap trace, range/overflow/IO checks |
| **Release** | `bin/release/<cpu>-<os>/cbzmanager` | -O3, smart linking, stripped symbols |

### From command line (Linux)

```bash
make build          # debug build with fpc (Qt6 widgetset)
make release        # release build (O3, smart link, strip)
make test           # compile and run FPCUnit test suite
make man            # lint the man page (requires groff)
make install        # install binary, man page, icon, and .desktop entry to /usr
make install-man    # install man page only to $(DESTDIR)$(PREFIX)/share/man/man1
make pkg            # build and install an Arch Linux package
make clean          # remove test build artifacts
```

### Headless (CLI) mode

The same binary doubles as a command-line tool: when launched with a known
command as its first argument it runs without any GUI (no display server
needed) and exits, otherwise the desktop application starts.

```bash
cbzmanager validate <dir>                 # verify CBZ files and images
cbzmanager convert-webp <dir> [--delete]  # convert images to WebP (quality 75%, only if smaller)
cbzmanager merge <dir> [--delete] [--force] [--chapters N1,N2,...] [--chapters-per-volume N]
cbzmanager cbr-to-cbz <dir> [--delete]    # convert CBR (RAR) archives to CBZ
cbzmanager --help
cbzmanager --version
```

- Flags may appear before or after the directory.
- Exit codes: `0` success (or a benign no-op such as "not enough chapters"),
  `1` runtime error, `2` usage error.
- `merge` processes every series found in the directory, one after the other.
- The commands mirror the Python reference CLI
  (`porting/cbz_manager`); `cbr-to-cbz` is a GUI/CLI extension with no
  Python counterpart, and `delete-pages`, `find-similar` and
  `delete-pages-by-id` are not ported.
- A man page is provided: `man/cbzmanager.1` — render it from the repo with
  `man -l man/cbzmanager.1`, or install it system-wide with
  `make install-man` and read `man cbzmanager`.

## Dependencies

### OpenSSL (optional)

Only the **Add image from internet** feature needs it; everything else works without it. All the search backends are HTTPS-only, and FreePascal 3.2.2 reaches TLS through OpenSSL loaded at runtime.

FPC 3.2.2 only knows the OpenSSL 1.0 and 1.1 library names, which is a problem on current systems:

- **Windows** ships nothing under the names FPC looks for (`libeay32.dll`, `ssleay32.dll`, `libssl-1_1-x64.dll`). Recent builds do carry an OpenSSL 3 pair in `System32`, so the application probes for `libcrypto-3-x64.dll` / `libssl-3-x64.dll` at startup and points FPC at whichever pair actually loads. If none is found, drop a matching `libcrypto` / `libssl` pair next to `cbzmanager.exe`.
- **Linux / macOS** resolve the unversioned `libssl.so` / `libcrypto.so` (or `.dylib`) that the distribution's OpenSSL package installs, so nothing special is needed.

When no library can be loaded the search reports it and names the files it wants, rather than failing with a bare "Could not initialize OpenSSL library".

### libwebp (optional)

Many CBZ files store pages as WebP. Decoding and encoding them requires **libwebp**, which is loaded dynamically at runtime — it is *not* needed to build the project.

If the library is missing the application still works: JPEG, PNG, BMP, and GIF archives display normally, while WebP-only archives show no thumbnail. The startup log (`cbzmanager.log`, next to the executable) records which library was loaded.

The loader searches for `libwebp.so.7`, `libwebp.so.6`, `libwebp.so`, `libwebpdecoder.so*` on Linux, `libwebp.dylib` / `libwebpdecoder.dylib` on macOS, and `libwebp.dll`, `webp.dll`, `libwebp-7.dll` or `libwebpdecoder.dll` on Windows. Only `WebPGetInfo`, `WebPDecodeBGRA`, and optionally `WebPEncodeBGRA` / `WebPFree` are used.

#### Linux

```bash
sudo apt install libwebp7        # Debian / Ubuntu
sudo dnf install libwebp         # Fedora / RHEL
sudo pacman -S libwebp           # Arch
```

#### macOS

```bash
brew install webp
```

#### Windows

Obtain `libwebp.dll` from a shared-library build (e.g. [vcpkg](https://vcpkg.io): `vcpkg install libwebp:x64-windows`) and place it **next to `cbzmanager.exe`**, together with `libsharpyuv.dll` if the build provides one:

```
bin\debug\x86_64-win64\
    cbzmanager.exe
    libwebp.dll
    libsharpyuv.dll
```

The DLL architecture must match the build target (64-bit DLL for x86_64-win64, etc.).

## Project structure

```
src/
  main.pas / main.lfm           Main form (UI + orchestration)
  uservicebase.pas               Base service class, file utilities
  uclimode.pas                   Headless (CLI) mode: argument parsing + dispatch
  uservicevalidate.pas           CBZ validation service
  userviceconvert.pas            WebP conversion service
  uservicemerge.pas              Chapter merge service
  uservicecbr.pas                CBR-to-CBZ conversion service
  uservicecomicinfo.pas          ComicInfo.xml management service
  uthreadservice.pas             Background thread runner for services
  uzipeditor.pas                 ZIP/CBZ read/write operations
  uzipcore.pas                   Low-level ZIP entry handling
  ucomicinfo.pas                 ComicInfo.xml parsing/generation
  uPageEditModel.pas             In-memory page editing model
  uimgutil.pas                   Image utility functions
  uwebp.pas                      libwebp FFI dynamic loader
  uarchive.pas                   libarchive FFI dynamic loader (CBR/RAR)
  uloaderthread.pas              Background thumbnail loader
  uimgsrc.pas                    Internet image search + download (no GUI, no temp files)
  ulog.pas                       Thread-safe file logger
  usettings.pas                  Persisted application settings
  udlgbase.pas                   Shared dialog chrome and helpers
  udlgvalidate.pas / .lfm       Validate CBZ dialog
  udlgwebp.pas / .lfm           Convert to WebP dialog
  udlgcbr.pas / .lfm            Convert CBR to CBZ dialog
  udlgmerge.pas / .lfm          Merge chapters dialog
  udlgcomicinfo.pas / .lfm      Remove ComicInfo.xml dialog
  udlgcomicinfoeditor.pas / .lfm  View/edit ComicInfo.xml dialog
  udlgseqbuilder.pas / .lfm     Volume sequence builder dialog
  udlgpageview.pas / .lfm       Floating page-view window
  udlgrows.pas / .lfm           Delete pages by range dialog
  udlgconvertresults.pas / .lfm  Conversion summary dialog
  udlgaddimage.pas / .lfm       Add image from internet dialog
  ufrmjobmonitor.pas / .lfm     Non-modal job monitor window
tests/
  testrunner.pp                  FPCUnit test runner
  test_helpers.pas               Shared test utilities
  test_uzipeditor.pas            ZIP editor tests
  test_uservicevalidate.pas      Validation service tests
  test_uclimode.pas              Headless CLI tests
  test_uservicemerge.pas         Merge service tests
  test_uservicecomicinfo.pas     ComicInfo service tests
  test_ucomicinfo.pas            ComicInfo XML parsing tests
  test_udlgpageview.pas          Floating page-view dialog tests
  test_uimgsrc.pas               Image search provider parser tests (offline)
man/
  cbzmanager.1                   Man page (section 1)
pkg/
  cbzmanager.desktop             FreeDesktop .desktop entry
  cbzmanager.svg                 Application icon (scalable)
  PKGBUILD                      Arch Linux package build script
```

## License

MIT — see [LICENSE](LICENSE).
