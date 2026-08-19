# CBZ Manager — Tauri Port Plan

## Architecture Decision

### Stack Selection: **Tauri v2 + Svelte 4**

| Layer | Choice | Rationale |
|-------|--------|----------|
| **Frontend** | Svelte 4 (TypeScript) | Lightweight, compiles away virtual DOM, excellent DX, zero-runtime overhead. The two-pane list/detail UI maps naturally to Svelte components. Small bundle (~50 KB gzipped).
| **Backend** | Tauri v2 (Rust) + CLI binary | Rust is the natural choice for memory-safe ZIP/image manipulation. Tauri provides IPC from the webview to Rust commands, but more importantly we retain the existing headless CLI as the primary execution path. |
| **ZIP handling** | `zip` crate (with `deflate` feature) | Replaces FPUnZipper / TZipper entirely. Drop-in parity with `uzipcore.pas`. |
| **Image decode** | `image` crate + `webp` crate | Replaces FPImage readers + uwebp.pas libwebp FFI. Covers JPEG, PNG, BMP, GIF, TIFF, WebP. |
| **Image encode** | `image` + `webp` crates | JPEG (quality 92), PNG, BMP lossless, WebP (quality 75). Replaces EncodeIntfImage. |
| **CBR support** | `libarchive` via `bindgen` / `libloading` | Same FFI pattern as uarchive.pas; dynamic loading at runtime so CBR is optional. |
| **XML parsing** | `quick-xml` | Replaces TDocProcessor from Lazarus's XMLReaders for ComicInfo.xml parse/generate. |
| **Settings** | `confy` crate | INI-style persistent settings, replaces usettings.pas (TIniFile). |
| **Logging** | `tracing` + `tracing-subscriber` | Thread-safe logger replacing ulog.pas. |

### Why NOT Electron / Tauri with React / Vue?
- Svelte's compile-time approach produces the smallest bundle and best performance for this kind of desktop app
- The UI is data-driven (two ListView → two List components), not a heavy SPA — no virtual DOM needed
- SvelteKit can be used if we want SSR later, but for now plain Vite + Svelte is sufficient
- React/Vue would add 30-50 KB overhead with no benefit for this use case

### Why NOT WebAssembly from Go/C++?
- Tauri natively supports Rust commands; WASM adds a build and IPC complexity layer
- The `image` crate ecosystem already covers our decode/encode needs without custom toolchain

---

## Project Structure

```
porting/tauri/
├── Cargo.toml                  # Rust workspace (CLI + Tauri app)
├── src/
│   ├── bin/cbzmanager.rs       # Headless CLI (existing Lazarus API → Rust port)
│   └── lib.rs                  # Re-export for Tauri
├── cbzmanager-tauri/
│   ├── Cargo.toml              # Tauri app package
│   ├── src/
│   │   ├── main.rs             # Tauri entry point (window, tray)
│   │   └── lib.rs              # Tauri command functions
│   ├── commands/
│   │   ├── mod.rs
│   │   ├── validate.rs         # Tauri cmd → crate::validate::validate()
│   │   ├── convert_webp.rs     # Tauri cmd → crate::convert_webp::convert()
│   │   ├── merge.rs            # Tauri cmd → crate::merge::merge()
│   │   ├── cbr_to_cbz.rs       # Tauri cmd → crate::cbr_to_cbz::convert()
│   │   ├── comicinfo.rs        # Tauri cmd → crate::comicinfo::scan_remove()
│   │   ├── page_edit.rs        # In-memory page model + save
│   │   └── archive_ops.rs      # List entries, read entry, first image
│   └── tauri.conf.json
├── web/                        # Svelte frontend (Vite project)
│   ├── package.json
│   ├── svelte.config.js
│   ├── vite.config.ts
│   ├── src/
│   │   ├── app.html
│   │   ├── main.ts
│   │   ├── routes/
│   │   │   └── +layout.svelte  # Main app layout (file browser + preview)
│   │   ├── components/
│   │   │   ├── FileBrowser.svelte    # Left pane: directory with file list thumbnails
│   │   │   ├── PagePreview.svelte    # Right pane: page grid/thumbnails
│   │   │   ├── ThumbnailGrid.svelte  # Reusable thumbnail display component
│   │   │   ├── StageBar.svelte       # Unsaved changes bar (save/revert)
│   │   │   ├── JobMonitor.svelte     # Non-modal progress window
│   │   │   ├── PageEditor.svelte     # Modal: resize/colour/split page operations
│   │   │   ├── BatchEdit.svelte      # Modal: batch resize/colour/split
│   │   │   ├── MergeDialog.svelte    # Chapter-to-volume merge dialog
│   │   │   ├── ValidateDialog.svelte # Validation results
│   │   │   ├── ConvertDialog.svelte  # WebP conversion options + results
│   │   │   ├── CbrDialog.svelte      # CBR→CBZ conversion dialog
│   │   │   ├── ComicInfoDialog.svelte# View/edit ComicInfo.xml
│   │   │   └── PageViewer.svelte     # Full-res page viewer (Space key)
│   │   ├── stores/
│   │   │   ├── files.ts       # File list state (selected, thumbnails)
│   │   │   ├── pages.ts       # Current file's page list + edits
│   │   │   ├── progress.ts    # Job monitor progress state
│   │   │   └── settings.ts    # App settings persistence
│   │   └── lib/
│   │       ├── api.ts         # Tauri IPC wrapper (invoke commands)
│   │       └── types.ts       # Shared TypeScript type definitions
│   └── static/                 # Icon, splash screen
├── rust-core/                  # Core service layer (no GUI dependency)
│   └── src/
│       ├── lib.rs
│       ├── zip_ops.rs          # CollectZipEntries ↔ WriteZipFromEntries port
│       ├── cbr_reader.rs       # CBR via libarchive FFI
│       ├── validate.rs         # TValidateService port (with parallel pool)
│       ├── convert_webp.rs     # TConvertService port (parallel decode+encode)
│       ├── merge.rs            # TMergeService port
│       ├── comicinfo.rs        # ComicInfo.xml scan/remove service
│       ├── cbr_convert.rs      # Batch CBR→CBZ conversion service
│       ├── image_edit.rs       # Resample, AdjustColors, SplitIntfImage
│       ├── batch_edit.rs       # TMultiEdit pipeline
│       ├── page_model.rs       # TPageState + TSaveChangesThread
│       ├── webp_decode.rs      # WebP decoder (libwebp FFI / crate)
│       ├── image_util.rs       # Format detection, encoding, scaling
│       └── types.rs            # Shared types: TZipEntry, TImageCheck, etc.
├── tests/                      # Rust integration tests
│   └── tests/
│       ├── test_validate.rs
│       ├── test_convert_webp.rs
│       ├── test_merge.rs
│       └── test_cbr_convert.rs
└── TARGET.md                   # This file
```

---

## File-by-File Port Mapping

### Core (GUI-free) — High Priority

| Lazarus File | Rust Module | Status |
|-------------|-------------|--------|
| `uzipcore.pas` | `rust-core/src/zip_ops.rs` (partially) | Foundation for all ZIP work |
| `uzipeditor.pas` | `rust-core/src/zip_ops.rs` + `convert_webp.rs` + `validate.rs` + `merge.rs` | Core operations: RAM-only ZIP read/write, conversion, validation |
| `uarchive.pas` | `rust-core/src/cbr_reader.rs` | libarchive FFI — same pattern as Pascal |
| `uservicebase.pas` | `rust-core/src/types.rs` + helpers | Progress types, BackupFile, ReplaceCBZ, CollectCBZFiles/CBRFiles |
| `uservicevalidate.pas` | `rust-core/src/validate.rs` | TValidateService::Validate + ValidateDeep |
| `userviceconvert.pas` | `rust-core/src/convert_webp.rs` | TConvertService::Convert (parallel pool) |
| `uservicemerge.pas` | `rust-core/src/merge.rs` | TMergeService classification, CPV calc, batching |
| `uservicecbr.pas` | `rust-core/src/cbr_convert.rs` | Batch CBR→CBZ conversion (parallel file pool) |
| `uservicecomicinfo.pas` | `rust-core/src/comicinfo.rs` | Scan + Remove ComicInfo.xml |
| `uimageedit.pas` | `rust-core/src/image_edit.rs` | ResampleIntfImage, AdjustColors, SplitIntfImage |
| `uimgutil.pas` | `rust-core/src/image_util.rs` | Decode/encode/format detection/scaling |
| `ubatchedit.pas` | `rust-core/src/batch_edit.rs` | TMultiEdit pipeline |
| `upageeditmodel.pas` | `rust-core/src/page_model.rs` | TPageState, TSaveChangesThread, page ops |
| `ucomicinfo.pas` | `rust-core/src/comicinfo_xml.rs` | ParseComicInfoXML / GenerateComicInfoXML |
| `uwebp.pas` | `rust-core/src/webp_decode.rs` | libwebp FFI or image crate WebP support |

### GUI — Low Priority (can be rebuilt from scratch)

| Lazarus File | Svelte Component | Notes |
|-------------|-----------------|-------|
| `main.pas`/`.lfm` | `routes/+layout.svelte` + stores | Two-pane UI, keyboard shortcuts, zoom, threading orchestration |
| `uloaderthread.pas` | Web Worker (via Tauri commands) | Thumbnail loading — not a native thread anymore, uses Tauri's async commands |
| `upreviewloader.pas` | (same as above) | Preview page loading via IPC |
| `ufrmjobmonitor.pas` + `.lfm` | `components/JobMonitor.svelte` | Non-modal progress overlay |
| `udlgvalidate.pas` + `.lfm` | `components/ValidateDialog.svelte` | Validation results table |
| `udlgwebp.pas` + `.lfm` | `components/ConvertDialog.svelte` | WebP conversion options/results |
| `udlgmerge.pas` + `.lfm` | `components/MergeDialog.svelte` | Merge chapters dialog with sequence preview |
| `udlgcbr.pas` + `.lfm` | `components/CbrDialog.svelte` | CBR→CBZ conversion options |
| `udlgcomicinfo.pas` + `.lfm` | `components/ComicInfoDialog.svelte` | Remove ComicInfo.xml confirmation |
| `udlgcomicinfoeditor.pas` + `.lfm` | `components/ComicInfoEditor.svelte` | View/edit ComicInfo.xml form |
| `udlgpageview.pas` + `.lfm` | `components/PageViewer.svelte` | Full-res page viewer (Space key) |
| `udlgpageeditor.pas` + `.lfm` | `components/PageEditor.svelte` | Modal page editor (resize/colour/split) |
| `udlgbatchedit.pas` + `.lfm` | `components/BatchEdit.svelte` | Batch edit dialog with live preview |
| `udlgseqbuilder.pas` + `.lfm` | `components/MergeDialog.svelte` (sequence builder is part of merge) | Sequence preview within merge dialog |
| `udlgrows.pas` + `.lfm` | (built into PagePreview or a small modal) | Delete rows by range — simple enough to inline |
| `usettings.pas` | `stores/settings.ts` + `tauri-plugin-store` | INI → Tauri's built-in config store |

---

## Implementation Phases

### Phase 1: Rust Core Library (no GUI)
**Goal**: Reproduce the headless CLI functionality in Rust.

1. **ZIP operations** (`zip_ops.rs`): CollectZipEntries, WriteZipFromEntriesDeflated, FreeZipEntries, StripComicInfo, FindComicInfoIndex, FormatPageName, PagePaddingFor
2. **Image utilities** (`image_util.rs` + `webp_decode.rs`): StreamToIntfImage → read from bytes, DetectImageFormat (magic bytes), EncodeIntfImage (write to bytes), ScaleIntfImage (using `image` crate resizing)
3. **WebP conversion** (`convert_webp.rs`): ConvertCBZToWebP with parallel worker pool — the crown jewel operation
4. **Validation** (`validate.rs`): ValidateCBZImages with parallel decode pool
5. **Merge service** (`merge.rs`): TMergeService classification, CPV calculation, batching
6. **Page model** (`page_model.rs`): TPageState, PageDeleteSelected, PageMoveUp/Down, etc., TSaveChangesThread logic
7. **Image editing** (`image_edit.rs`): ResampleIntfImage (box filter), AdjustColors (pipeline), SplitIntfImage
8. **Batch edit** (`batch_edit.rs`): ApplyMultiEditToImage pipeline
9. **ComicInfo.xml** (`comicinfo_xml.rs` + `comicinfo.rs`): Parse and Generate XML, scan/remove service
10. **CBR reader** (`cbr_reader.rs`): libarchive FFI for RAR reading — dynamic loading
11. **CBR conversion** (`cbr_convert.rs`): Batch CBR→CBZ service
12. **CLI binary** (`cbzmanager`): Same CLI interface as current Pascal CLI

**Milestones**: After Phase 1, the Rust `cbzmanager` binary can do everything the Lazarus CLI does (validate, convert-webp, merge, cbr-to-cbz) with the same exit codes and argument parsing.

### Phase 2: Tauri Shell + Services
**Goal**: Frontend communicates with Rust backend via Tauri commands.

1. Set up Tauri v2 project structure
2. Implement IPC layer: `archive::list_entries(file)`, `archive::read_entry(file, name) → bytes[]`, `archive::first_image(file) → bytes[]`
3. Port services to Tauri commands (wrap Rust service calls)
4. Implement progress reporting via Tauri events (Tauri's event system replaces TThread.Queue)
5. Settings persistence using Tauri's config store

### Phase 3: Svelte Frontend
**Goal**: Rebuild the two-pane UI in Svelte.

1. File browser panel (left) — ListView → svelte:each loop with thumbnails
2. Page preview panel (right) — page grid with zoom slider
3. Stage bar component (unsaved changes indicator)
4. Job monitor overlay
5. All dialog components (validate, convert, merge, etc.)
6. Page editor modal (resize sliders, colour adjust, split lines)
7. Batch edit dialog with live preview
8. Full-res page viewer (Space key, center-anchored zoom/pan)
9. Keyboard shortcuts (F4, F5, F8, Ctrl+S, Ctrl+A, Space, Del)
10. Context menus and toolbar

### Phase 4: Polish & Testing
1. Cross-platform build verification (Linux, Windows, macOS)
2. E2E testing (Puppeteer/Playwright for Tauri's webview)
3. Accessibility improvements
4. Performance profiling (thumbnail generation speed, zoom responsiveness)
5. Binary size optimization
6. Distribution packaging (deb, rpm, AppImage, MSI, DMG)

---

## Key Technical Challenges & Solutions

### 1. Image Decoding Performance
**Challenge**: FPImage readers are highly optimized for their formats. Rust's `image` crate covers the formats but may not match FPC's raw speed.
**Solution**: Use `image` crate with specific decoder backends (`jpeg-decoder`, `png`, `webp`). For WebP, use `webp` crate (libwebp bindings) which matches uwebp.pas directly. Profile and optimize if needed — the parallel worker pool already amortizes decode cost.

### 2. CBR / libarchive Integration
**Challenge**: Dynamic loading of native library across platforms.
**Solution**: Same FFI pattern as Lazarus. Use `libloading` crate on Linux/macOS, `windows` crate for DLL path on Windows. Check availability at runtime and degrade gracefully (no CBR thumbnails + informative message).

### 3. Thumbnail Generation Speed
**Challenge**: LCL's TLazIntfImageList → TBitmap conversion is done in the main thread. Web views have no bitmap API.
**Solution**: Generate PNG-encoded byte arrays in Rust (fast, lossless, small), send to frontend as `ArrayBuffer`, decode on the browser side with `createImageBitmap()` for GPU-accelerated rendering. This avoids any format conversion overhead in the IPC layer.

### 4. Threading Model Changes
**Challenge**: Lazarus uses OS threads + TThread.Queue. Web views use JavaScript's event loop + web workers.
**Solution**: Tauri commands run on Rust's async runtime (Tokio), which handles parallelism naturally. The frontend receives progress updates via Tauri events (similar to TThread.Queue). No web worker needed — the Tauri backend handles all heavy I/O.

### 5. Deterministic Output
**Challenge**: Parallel WebP conversion must produce byte-identical output regardless of thread count.
**Solution**: Same architecture as Pascal: phase 1 (parallel encode) fills per-slot buffers, phase 2 (sequential compaction) reads slots in archive order. This is preserved in the Rust implementation.

---

## Non-Goals (Out of Scope)

The following Lazarus-specific concerns are explicitly out of scope:
- LCL widgetset migration (we're replacing it entirely)
- Pascal/FPC compilation pipeline
- FPCUnit test suite (replaced by Rust `cargo test` + Playwright E2E)
- Qt6 desktop integration (native Tauri window management replaces this)
- Lazarus form designer (.lfm files — rebuild from scratch in Svelte)

---

## Migration Strategy: Parallel Development

The current Lazarus build remains the source of truth during development. The strategy is:

1. **Phase 1 runs in parallel**: Implement Rust core, verify against Pascal CLI via differential tests (same input → same output archives)
2. **Phase 2+ can start while Phase 1 finishes**: UI components don't depend on backend completion — mock commands for prototyping
3. **Feature parity checklist**:
   - [ ] validate --threads N (quick + deep)
   - [ ] convert-webp [--delete] [--threads N]
   - [ ] merge [--delete] [--force] [--chapters] [--chapters-per-volume]
   - [ ] cbr-to-cbz [--delete] [--threads N]
   - [ ] remove-comicinfo [--backup]
   - [ ] Preview pane (CBZ + CBR thumbnails)
   - [ ] Page editing (delete, reorder, sort, reverse, renumber)
   - [ ] Stage bar with save/revert
   - [ ] Page editor modal (resize, colour adjust, split)
   - [ ] Batch edit dialog
   - [ ] Job monitor overlay
   - [ ] Full-res page viewer (Space key)
   - [ ] ComicInfo.xml view/edit
   - [ ] Keyboard shortcuts
   - [ ] Settings persistence

---

## Estimated Effort

| Phase | Estimated Time | Key Deliverable |
|-------|---------------|-----------------|
| Phase 1: Rust Core | 60-80 hours | CLI binary with full parity to current Pascal CLI |
| Phase 2: Tauri Shell | 20-30 hours | Working IPC layer, services callable from frontend |
| Phase 3: Svelte Frontend | 50-70 hours | Complete two-pane UI with all dialogs and interactions |
| Phase 4: Polish & Testing | 20-30 hours | Cross-platform builds, E2E tests, packaging |
| **Total** | **150-210 hours** | Feature-complete Tauri + Svelte application |

---

## Dependencies Checklist (Rust ecosystem)

| Function | Crate | Notes |
|----------|-------|-------|
| ZIP read/write | `zip` (=0.6), `flate2` | Deflate compression, central directory handling |
| Image decode | `image` (=0.24) with features: `jpeg`, `png`, `bmp`, `gif`, `webp`, `tiff` | Multi-format decoding |
| WebP encode | `webp` (libwebp bindings) OR `image` + `image-webp` | Match uwebp.pas quality settings |
| XML parsing | `quick-xml` = "0.30" | ComicInfo.xml parse/generate |
| CBR support | `libloading`, `bindgen` (or manual FFI) | Dynamic libarchive loading |
| Settings | `confy` | INI-style persistent config |
| Logging | `tracing`, `tracing-subscriber` | Thread-safe logger |
| CLI parsing | `clap` = "4" | Argument parsing (--threads, --delete, etc.) |
| Async runtime | `tokio` (feature: full) | Tauri backend uses this natively |
| Image manipulation | `imageproc` (optional) | For Resample/Scale operations if image crate's resize isn't sufficient |
| Cross-platform paths | `dirs` + `path-absolutize` | App config dir, path operations |

---

## Why This Architecture?

1. **Rust for core logic**: Memory safety for ZIP manipulation (no buffer overflows like C/C++), zero-cost abstractions for parallel pools, excellent crates ecosystem for archive/image work
2. **Tauri v2 for shell**: Small binary size (~3 MB vs ~80 MB for Electron), native system integration, modern IPC API
3. **Svelte for UI**: Minimal runtime overhead means faster rendering of thumbnail grids (critical for responsiveness with 100+ pages). The component model maps cleanly to the Lazarus form/dIALOG structure.
4. **Preserves CLI interface**: The Rust core is designed to support both CLI mode (exact parity) and Tauri IPC, maximizing reuse of business logic.

## Divergences from Lazarus (Intentional)

1. **No LCL dependency**: The entire UI is HTML/CSS/JS — renders identically on all platforms without widgetset quirks
2. **Web-native image display**: Thumbnails served as PNG byte arrays, rendered via browser's `createImageBitmap()` instead of TLazIntfImageList → TBitmap pipeline
3. **Async I/O model**: Rust async (Tokio) replaces OS threads + TThread.Queue — simpler API for developers, better error propagation
4. **No .lfm form files**: All UI layout is in Svelte components with CSS — more flexible than the Lazarus form designer
5. **Native WebP encoding via `webp` crate**: Eliminates dynamic libwebp loading (the Rust crate bundles libwebp), making WebP conversion work out-of-the-box on all platforms
