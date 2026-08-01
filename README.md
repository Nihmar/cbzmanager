# cbzmanager

A FreePascal / Lazarus desktop application for managing CBZ (Comic Book ZIP) files.

## Features

- **Validate** — verify CBZ archives are valid ZIPs with non-corrupted images (JPEG, PNG, BMP, GIF, WebP)
- **Convert to WebP** — re-encode images as WebP (configurable quality), keeping originals only when smaller; rename to `page_NNNN.*`; optional `_OLD.cbz` backup
- **Merge chapters** — combine chapter files (`Title - NNNN.cbz`) into volumes (`Title VNNN.cbz`) with auto-calculated chapters-per-volume
- **In-place page editor** — delete, reorder, sort, reverse, and renumber pages inside a single CBZ with live preview, stage bar (save/revert), and optional backup toggle
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
make build          # compile with fpc (Qt6 widgetset)
make test           # compile and run FPCUnit test suite
make man            # lint the man page (requires groff)
make install-man    # install man page to $(DESTDIR)$(PREFIX)/share/man/man1 (PREFIX default: /usr/local)
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
cbzmanager --help
cbzmanager --version
```

- Flags may appear before or after the directory.
- Exit codes: `0` success (or a benign no-op such as "not enough chapters"),
  `1` runtime error, `2` usage error.
- `merge` processes every series found in the directory, one after the other.
- The commands mirror the Python reference CLI
  (`porting/cbz_manager`); `delete-pages`, `find-similar` and
  `delete-pages-by-id` are not ported.
- A man page is provided: `man/cbzmanager.1` — render it from the repo with
  `man -l man/cbzmanager.1`, or install it system-wide with
  `make install-man` and read `man cbzmanager`.

## Dependencies

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
  uservicecomicinfo.pas          ComicInfo.xml management service
  uthreadservice.pas             Background thread runner for services
  uzipeditor.pas                 ZIP/CBZ read/write operations
  uzipcore.pas                   Low-level ZIP entry handling
  ucomicinfo.pas                 ComicInfo.xml parsing/generation
  uPageEditModel.pas             In-memory page editing model
  uimgutil.pas                   Image utility functions
  uwebp.pas                      libwebp FFI dynamic loader
  uloaderthread.pas              Background thumbnail loader
  ulog.pas                       Thread-safe file logger
  usettings.pas                  Persisted application settings
  udlgbase.pas                   Shared dialog chrome and helpers
  udlgvalidate.pas / .lfm       Validate CBZ dialog
  udlgwebp.pas / .lfm           Convert to WebP dialog
  udlgmerge.pas / .lfm          Merge chapters dialog
  udlgcomicinfo.pas / .lfm      Remove ComicInfo.xml dialog
  udlgcomicinfoeditor.pas / .lfm  View/edit ComicInfo.xml dialog
  udlgseqbuilder.pas / .lfm     Volume sequence builder dialog
  udlgrows.pas / .lfm           Delete pages by range dialog
  udlgconvertresults.pas / .lfm  Conversion summary dialog
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
man/
  cbzmanager.1                   Man page (section 1)
```

## License

MIT — see [LICENSE](LICENSE).
