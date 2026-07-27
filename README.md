# cbzmanager

A FreePascal / Lazarus desktop application for managing CBZ (Comic Book ZIP) files.

## Features

- **Validate** — verify CBZ archives are valid ZIPs with non-corrupted images (JPEG, PNG, BMP, GIF, WebP)
- **Convert to WebP** — re-encode images as WebP (configurable quality), keeping originals only when smaller; rename to `page_NNNN.*`; optional `_OLD.cbz` backup
- **Merge chapters** — combine chapter files (`Title - NNNN.cbz`) into volumes (`Title VNNN.cbz`) with auto-calculated chapters-per-volume
- **In-place page editor** — delete, reorder, sort, reverse, and renumber pages inside a single CBZ with live preview and save/revert workflow
- **ComicInfo.xml** — view, edit, remove, or generate `ComicInfo.xml` metadata embedded in CBZ archives
- **Sequence builder** — define custom volume/chapter grouping sequences for non-standard merge layouts

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
make clean          # remove test build artifacts
```

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
  uservicevalidate.pas           CBZ validation service
  userviceconvert.pas            WebP conversion service
  uservicemerge.pas              Chapter merge service
  uservicecomicinfo.pas          ComicInfo.xml management service
  uthreadservice.pas             Background thread runner for services
  uzipeditor.pas                 ZIP/CBZ read/write operations
  ucomicinfo.pas                 ComicInfo.xml parsing/generation
  uPageEditModel.pas             In-memory page editing model
  uimgutil.pas                   Image utility functions
  uwebp.pas                      libwebp FFI dynamic loader
  uloaderthread.pas              Background thumbnail loader
  ulog.pas                       Thread-safe file logger
  udlg*.pas / udlg*.lfm         Operation dialogs (7 dialogs)
tests/
  testrunner.pp                  FPCUnit test runner
  test_helpers.pas               Shared test utilities
  test_uzipeditor.pas            ZIP editor tests
  test_uservicevalidate.pas      Validation service tests
  test_uservicemerge.pas         Merge service tests
  test_uservicecomicinfo.pas     ComicInfo service tests
```

## License

MIT — see [LICENSE](LICENSE).
