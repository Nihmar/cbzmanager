# Plan: CBZ Manager Port from Lazarus/Pascal to Tauri v2 + Svelte 4 + Rust

## Goal & Success Criteria

**Goal**: Reproduce the full feature set of the existing Lazarus/CBZ Manager (3,072-line `main.pas` + 62 `.pas`/`.lfm` GUI files + CLI) as a Tauri v2 desktop application with a Rust core library and Svelte 4 frontend.

**Success Criteria**:
1. **Feature parity**: All 6 operations work identically (validate, convert-webp, merge, remove-comicinfo, cbr-to-cbz, page-edit). CLI matches Pascal CLI argument parsing, exit codes (0 success/benign-no-op, 1 runtime error, 2 usage), and flag behavior.
2. **Deterministic output**: Parallel WebP conversion produces byte-identical archives regardless of thread count (same phase-then-compact architecture as Pascal).
3. **In-RAM only**: All ZIP/CBR operations use streams — no temp files on disk. Final write is the only disk I/O.
4. **CBR graceful degradation**: App works without libarchive; CBR previews disabled, cbr-to-cbz exits 1 with message.
5. **Performance**: Thumbnail grid renders smoothly at 100+ pages. Page edit operations complete within acceptable time.

---

## Checkpoints — where to resume (start each session here)

| # | Checkpoint | What's done | Next step |
|---|-----------|-------------|-----------|
| 0 | **Scaffolding** | Workspace, 3 crates compile | Types |
| 1 | **Shared types + helpers** | Types, constants, backup/rename utilities | ZIP ops |
| 2 | **ZIP operations** | CollectZipEntries, WriteZipFromEntries, FormatPageName, ComicInfo filtering | Image util |
| 3 | **Image utilities** | Magic-byte detection, decode/encode/scale, center-anchor scroll math | Services |
| 4 | **All services** | validate, convert-webp, merge, comicinfo, cbr-reader, cbr-convert, image-edit, batch-edit, page-model | CLI binary |
| 5 | **CLI binary** | `cbzmanager` headless with all commands, matching Pascal exit codes | Tauri shell |
| 6 | **Tauri shell + IPC** | Commands wrap rust-core, progress events, settings, logging | Frontend stores + API |
| 7 | **Frontend — stores + API + types** | Svelte store wiring, `api.ts`, TypeScript types | Core UI components |
| 8 | **Frontend — core UI** | Two-pane layout, file browser, page preview, stage bar, job monitor, main layout | Dialogs |
| 9 | **Frontend — all dialogs** | Validate, convert, merge, CBR, comicinfo, viewer, editor, batch-edit, results | Polish & tests |
| 10 | **Polish & tests** | Rust unit/integration tests, E2E, cross-platform builds, packaging | Done |

> **Legend**: `[ ]` not started · `[~]` in progress · `[x]` done
> Scroll to the first `[ ]` in your current checkpoint and start there.

---

## Phase 1: Rust Core Library (no GUI) — ~70-95h

### Checkpoint 0 — Scaffolding

**Files to create:** `Cargo.toml` (workspace), `rust-core/`, `cbzmanager-cli/`, `cbzmanager-tauri/`

- [ ] **0A.** Create workspace `porting/tauri/Cargo.toml` with three members: `rust-core/`, `cbzmanager-cli/`, `cbzmanager-tauri/`
- [ ] **0B.** Create `porting/tauri/rust-core/Cargo.toml` — core library crate
- [ ] **0C.** Create `porting/tauri/cbzmanager-cli/Cargo.toml` — CLI binary crate (`--no-default-features --features cli-only`)
- [ ] **0D.** Create `porting/tauri/cbzmanager-tauri/Cargo.toml` — Tauri app crate (default = `"gui"` includes Tauri)
- [ ] **0E.** Verify workspace compiles: `cargo check --workspace`
- [ ] **0F.** Set up feature flags in root:
  ```toml
  [features]
  default = ["gui"]
  gui = ["tauri"]
  cli-only = []  # implies no tauri dep, just binary crate
  ```

**Dependency decisions (from TARGET.md):**

| Crate | Version | Use |
|-------|---------|-----|
| `zip` | 0.6 | ZIP read/write, deflate compression |
| `flate2` | — | Deflate backend for zip crate |
| `image` | 0.25 with `default,jpeg,webp,png,bmp,gif,tiff` features | Multi-format decode/encode; GIF encoding requires explicit `gif` flag |
| `webp` | latest | WebP encoding (bundles libwebp, no runtime dependency) |
| `quick-xml` | 0.37 | ComicInfo.xml parse/generate |
| `libloading` | latest | Dynamic libarchive loading |
| `clap` | 4 | CLI argument parsing |
| `tokio` | full | Async runtime for Tauri |
| `tracing` / `tracing-subscriber` | latest | Structured logging |
| `thiserror` | latest | Domain error types |
| `dirs` | latest | App config directory |
| `rayon` | latest | CPU-parallel worker pools |

---

### Checkpoint 1 — Shared types + helpers

**Replaces:** `uservicebase.pas` — `TZipEntry`, `TImageCheck`, progress callback types, constants

```rust
// Public types:
pub struct ZipEntry { name: String, data: Vec<u8> }     // from CollectZipEntries
pub struct ImageCheckResult { ok: bool, errors: Vec<String>, depth: usize }  // from validate
pub enum ArchiveType { Cbz, Cbr }
pub const BACKUP_SUFFIX: &str = "_OLD.cbz";
pub const CBZ_EXT: &str = ".cbz";
pub const CBR_EXT: &str = ".cbr";
pub const MAX_WEBP_THREADS: usize = 8;
pub const MAX_CBR_THREADS: usize = 4;

// Progress: use a closure/Fn callback pattern instead of Pascal method pointers.
// TLockedProgress equivalent: wrap Fn in Mutex or use tokio::sync::Mutex for async contexts.
// CLI mode uses no progress callback (stdout/stderr). Tauri commands emit events.
```

- [ ] **1A.** Create `rust-core/src/types.rs` with all public types above
- [ ] **1B.** Create helper functions in same file or a separate `helpers.rs`:
  - [ ] `backup_file(path: &Path) -> Result<PathBuf>` — rename to `._OLD.cbz`
  - [ ] `replace_cbz(original: &Path, replacement: &Path) -> Result<()>` — atomic replace
  - [ ] `collect_cbz_files(dir: &Path) -> Vec<PathBuf>` — glob `.cbz` / `.CBZ` (case-insensitive)
  - [ ] `collect_cbr_files(dir: &Path) -> Vec<PathBuf>` — glob `.cbr` / `.CBR` (case-insensitive)

---

### Checkpoint 2 — ZIP operations

**Replaces:** `uzipcore.pas` + `uzipeditor.pas` (collection/writing parts)

| Pascal | Rust | Details |
|--------|------|---------|
| `CollectZipEntries` | `collect_zip_entries(path: &Path) -> Result<Vec<ZipEntry>>` | Open ZIP, read each entry into Vec<u8>, skip ComicInfo.xml |
| `WriteZipFromEntries` | `write_zip_from_entries(path: &Path, entries: &[ZipEntry]) -> Result<()>` | Create ZIP (deflate), write entries in order |
| `FreeZipEntries` | — | Rust owns Vec, dropped naturally |
| `StripComicInfo` | Inline in collect | Filter during collection; no separate pass needed |
| `FindComicInfoIndex` | `find_comicinfo_index(entries: &[String]) -> Option<usize>` | Search for ComicInfo.xml by name |
| `FormatPageName` | `format_page_name(index: usize, padding: usize) -> String` | `page_0001.ext` (zero-padded) |
| `PagePaddingFor` | `page_padding_for(count: usize) -> usize` | Padding = count digits |

**Key invariant:** All operations are RAM-only. `collect_zip_entries` opens the ZIP and reads each entry via compression reader into Vec<u8>. `write_zip_from_entries` creates a fresh ZIP writer (deflate level defaults to 6/ZIP_DEFAULT_COMPRESSION, matching Pascal).

- [ ] **2A.** Create `rust-core/src/zip_ops.rs`
- [ ] **2B.** Implement `collect_zip_entries(path: &Path) -> Result<Vec<ZipEntry>>` — open ZIP, read entries into Vec<u8>, skip ComicInfo.xml during collection
- [ ] **2C.** Implement `write_zip_from_entries(path: &Path, entries: &[ZipEntry]) -> Result<()>` — create ZIP with deflate compression, write entries in order
- [ ] **2D.** Implement `find_comicinfo_index(entries: &[String]) -> Option<usize>` — search for ComicInfo.xml by name
- [ ] **2E.** Implement `format_page_name(index: usize, padding: usize) -> String` and `page_padding_for(count: usize) -> usize`

---

### Checkpoint 3 — Image utilities

**Replaces:** `uimgutil.pas` + `uwebp.pas`

```rust
// Magic-byte detection (same as Pascal):
pub fn detect_format(bytes: &[u8]) -> ImageFormat { Jpeg | Png | Webp | Bmp | Gif | Tiff }

// Decode: read bytes → DynamicImage (from image crate)
pub fn decode_image(bytes: &[u8]) -> Result<DynamicImage>;

// Encode back to bytes (replaces EncodeIntfImage):
pub fn encode_image(img: &DynamicImage, format: ImageFormat, quality: u32) -> Result<Vec<u8>>;
  // JPEG at q92, WebP at q75, PNG/BMP lossless. GIF/TIFF → PNG (no FPC encoder for them).

// Scale / resample (replaces ResampleIntfImage + ScaleIntfImage):
pub fn scale_image(img: &DynamicImage, width: u32, height: u32) -> DynamicImage;
  // Box filter — image crate's resize_exact with FilterType::Box

// Center anchor scroll math (same algorithm as Pascal's CenterAnchorScrollPos):
pub fn center_anchor(delta: f64, current_zoom: f64, new_zoom: f64, img_w: u32, view_w: u32, pos_x: f64) -> f64;
```

**WebP decode:** The `image` crate already supports WebP via the `webp` feature flag. However, Pascal's `uwebp.pas` uses libwebp FFI for raw decoding. Use `image` crate first — if pixel-exact parity is needed later, add a separate `webp_decode.rs` with libwebp FFI matching Pascal's approach.

- [ ] **3A.** Create `rust-core/src/image_util.rs`
- [ ] **3B.** Implement magic-byte format detection: `detect_format(bytes: &[u8]) -> ImageFormat { Jpeg, Png, Webp, Bmp, Gif, Tiff }`
- [ ] **3C.** Implement `decode_image(bytes: &[u8]) -> Result<DynamicImage>` via image crate
- [ ] **3D.** Implement `encode_image(img: &DynamicImage, format: ImageFormat, quality: u32) -> Result<Vec<u8>>` — JPEG q92, WebP q75, PNG/BMP lossless; GIF/TIFF → PNG
- [ ] **3E.** Implement `scale_image(img: &DynamicImage, width: u32, height: u32) -> DynamicImage` — box filter (`FilterType::Box`)
- [ ] **3F.** Implement `center_anchor(delta, current_zoom, new_zoom, img_w, view_w, pos_x) -> f64` — same algorithm as Pascal
- [ ] **3G.** Implement thumbnail generation pipeline: `generate_thumbnail(bytes: &[u8], cache_width: u32) -> Result<Vec<u8>>` (decode → scale → JPEG encode as base64 for frontend)

---

### Checkpoint 4 — All services (core modules)

Each service is a separate module. They can be built in any order but depend on checkpoints 0-3.

#### 4A. Validation (`rust-core/src/validate.rs`)
**Replaces:** `uservicevalidate.pas`

```rust
pub fn validate(path: &Path, threads: usize) -> Result<Vec<FileValidationResult>>;
pub fn validate_deep(path: &Path, threads: usize) -> Result<Vec<FileValidationResult>>;
// FileValidationResult: { path: PathBuf, ok: bool, errors: Vec<ImageCheck> }
// ImageCheck: { filename: String, depth: usize, ok: bool, errors: Vec<String> }
```

- [ ] **4A.1.** Implement `validate()` — quick mode (just open + read image headers)
- [ ] **4A.2.** Implement `validate_deep()` — full decode + re-encode test
- [ ] **4A.3.** Parallel pool via rayon (same phase-then-gather pattern as Pascal `TValidateWorker`)
- [ ] **4A.4.** Determinism: threads=1 vs rayon → identical results per slot

#### 4B. Convert-webp (`rust-core/src/convert_webp.rs`)
**Replaces:** `userviceconvert.pas`

```rust
pub fn convert(path: &Path, threads: usize, delete_source: bool) -> Result<ConversionResult>;
// ConversionResult: { converted: Vec<PathBuf>, skipped: Vec<PathBuf> }
```

Architecture (same as Pascal — deterministic): 1. Collect entries into RAM → 2. Parallel phase (claim convertible entry → decode → encode WebP q75 → check size → store in per-slot buffer) → 3. Sequential phase (iterate archive order, compact slots, filter ComicInfo.xml, renumber as `page_NNNN.webp`) → 4. Write ZIP → 5. Backup or delete source.

- [ ] **4B.1.** Implement `convert()` with parallel rayon worker pool
- [ ] **4B.2.** Phase 1 (parallel) + Phase 2 (sequential compaction) for deterministic output
- [ ] **4B.3.** Write ZIP and handle backup/deletion
- [ ] **4B.4.** Determinism: threads=1 vs 4 → byte-identical archives

#### 4C. Merge (`rust-core/src/merge.rs`) — most intricate business logic
**Replaces:** `uservicemerge.pas`

```rust
pub enum MergeConfig { Chapters(Vec<usize>), ChaptersPerVolume(usize) }
pub fn merge(dir, force, config, chapter_start, chapter_end, generate_comicinfo, threads) -> Result<Vec<MergeVolume>>;

pub struct MergeVolume { title: String, output_path: PathBuf, chapters: Vec<PathBuf>, comicinfo_xml: Option<Vec<u8>> }
```

**Intentional divergences (all from TARGET.md):** non-image entries dropped; force below CPV creates single volume; CPV < 1 with volumes present falls back to 7; `.CBZ` glob case-insensitive; empty batches produce no volume file; `GenerateComicInfo.xml` per volume is GUI-only option; multi-series folders merged per series; CPV = `(lowest_chapter - 1) / num_volumes` real division, integer result.

- [ ] **4C.1.** Implement chapter classification: detect series name and chapter numbers from filenames
- [ ] **4C.2.** Implement CPV calculation: `(lowest_chapter - 1) / num_volumes`, fallback to 7 if 0 or empty
- [ ] **4C.3.** Implement batching into volumes with `Series VNNN.cbz` naming
- [ ] **4C.4.** Implement per-file merge: collect entries from each chapter CBZ → write volume ZIP
- [ ] **4C.5.** Optional ComicInfo.xml generation per volume
- [ ] **4C.6.** All intentional divergences documented and tested

#### 4D. ComicInfo XML (`rust-core/src/comicinfo_xml.rs`)
**Replaces:** `ucomicinfo.pas`

```rust
pub struct ComicInfo { series, number, volume, count, genre, summary, publisher, imprint, year, month, day, writers[], inkers[], colorists[], letterers[], cover_artists[], tags[], groups[], launch_date }
pub fn parse_comicinfo_xml(xml: &[u8]) -> Result<ComicInfo>;
pub fn generate_comicinfo_xml(ci: &ComicInfo) -> Vec<u8>; // sorted element order matching Pascal for round-trip
```

- [ ] **4D.1.** Define `ComicInfo` struct with all fields
- [ ] **4D.2.** Implement `parse_comicinfo_xml()` via `quick-xml`
- [ ] **4D.3.** Implement `generate_comicinfo_xml()` — sorted element order matching Pascal for snapshot testing

#### 4E. ComicInfo service (`rust-core/src/comicinfo.rs`)
**Replaces:** `uservicecomicinfo.pas`

```rust
pub enum ComicInfoAction { Scan, Remove }
pub fn scan_or_remove(dir, action, threads, backup) -> Result<Vec<ComicInfoResult>>;
```

- [ ] **4E.1.** Implement scan and remove actions with parallel rayon pool
- [ ] **4E.2.** Backup file created before batch starts (same pattern as Pascal)

#### 4F. CBR reader (`rust-core/src/cbr_reader.rs`)
**Replaces:** `uarchive.pas`

```rust
pub fn cbr_entry_names(path: &Path) -> Result<Vec<String>>;     // names pass
pub fn foreach_cbr_image<F>(path: &Path, callback: F) -> Result<()> where F: FnMut(&str, &[u8]);
fn load_libarchive() -> Option<LibarchiveHandle>;
```

- [ ] **4F.1.** Implement dynamic loading: `load_libarchive()` — attempt `.so` on Linux, `.dll` on Windows; return `Err("libarchive not found")` if unavailable
- [ ] **4F.2.** Two-pass RAR scanning: first pass collects names for alphabetical ranking, second pass reads data

#### 4G. CBR conversion (`rust-core/src/cbr_convert.rs`)
**Replaces:** `uservicecbr.pas`

```rust
pub fn convert_cbr_to_cbz(dir, threads, delete_source) -> Result<Vec<CbrConversionResult>>;
// CbrConversionResult: { input: PathBuf, output: PathBuf, ok: bool, error: Option<String> }
```

**Parallel unit:** whole file (not per-image), because RAR decompression inside libarchive is single-threaded. Cap at 4 workers (each holds a full decompressed archive in RAM).

- [ ] **4G.1.** Implement batch CBR→CBZ conversion with rayon pool (one worker per `.cbr` index)
- [ ] **4G.2.** Optional source delete support

#### 4H. Image editing (`rust-core/src/image_edit.rs`)
**Replaces:** `uimageedit.pas`

```rust
pub fn resample_image(img, width, height) -> DynamicImage;        // Box filter, both directions
pub fn adjust_colors(img, params: ColorParams) -> DynamicImage;    // invert → grayscale → sepia → RGB gains → saturation → contrast → brightness → gamma (sequential)
pub struct CutLine { x1: f64, y1: f64, x2: f64, y2: f64 };       // normalized 0-1 coords
pub fn split_image(img, cuts: &[CutLine]) -> Vec<DynamicImage>;   // N parallel cut lines → N+1 pieces (scanline intersection rasterization)
```

- [ ] **4H.1.** Implement `resample_image()` — box filter, both directions (downscale and upscale)
- [ ] **4H.2.** Implement `adjust_colors()` — full pipeline applied sequentially to pixel data
- [ ] **4H.3.** Implement `split_image()` with scanline intersection rasterization

#### 4I. Batch edit (`rust-core/src/batch_edit.rs`)
**Replaces:** `ubatchedit.pas`

```rust
pub struct MultiEditParams { resize_percent, color_adjust, cut_lines }
pub fn apply_multi_edit(pages: &[PageState], params) -> Result<Vec<PageState>>;
```

- [ ] **4I.1.** Implement sequential RAM-only pipeline per page: decode → resize → colours → split → encode
- [ ] **4I.2.** Progress tracking via callback

#### 4J. Page model (`rust-core/src/page_model.rs`)
**Replaces:** `upageeditmodel.pas`

```rust
pub struct PageState { orig_name, name, data: Option<Vec<u8>>, deleted }
pub struct PageModel { pages, baseline: Vec<PageState>, changes: Vec<Change> }
impl PageModel { delete_at, move_up, move_down, sort_asc, sort_desc, reverse, renumber, insert_at, has_changes, revert; }
pub fn save_changes(pages, output_path, backup_path) -> Result<()>;
```

**Key behaviors:** `ckDeleted` excluded from output; changes recorded for undo; ZIP write entirely in RAM; `Data` stream wins over archive entry content; `OrigName` kept for replace mode.

- [ ] **4J.1.** Define `PageState` and `PageModel` structs
- [ ] **4J.2.** Implement page operations: delete_at, move_up, move_down, sort_asc, sort_desc, reverse, renumber, insert_at
- [ ] **4J.3.** Implement `has_changes()`, `revert()`, and `save_changes()` — Data wins over archive entry

---

### Checkpoint 5 — CLI binary

**Replaces:** `uclimode.pas`

```rust
#[derive(clap::Parser)] #[command(name = "cbzmanager", version, about)]
struct Cli { #[command(subcommand)] command: Command }
enum Command { Validate, ConvertWebp, Merge, CbrToCbz }
```

Exit codes: 0 success/benign-no-op, 1 runtime error, 2 usage error. Flags may precede or follow directory (clap's flexibility). Mutual exclusion of `--chapters` and `--chapters-per-volume` returns 1.

- [ ] **5A.** Create `cbzmanager-cli/src/main.rs`
- [ ] **5B.** Implement clap CLI with subcommands: `validate <dir> [--threads N]`, `convert-webp <dir> [--delete] [--threads N]`, `merge <dir> [--delete] [--force] [--chapters N1,N2] [--chapters-per-volume N]`, `cbr-to-cbz <dir> [--delete] [--threads N]`
- [ ] **5C.** Dispatch each command to corresponding rust-core function
- [ ] **5D.** Implement exit codes: 0, 1, 2 (mutual exclusion of `--chapters` / `--chapters-per-volume` → exit 1)
- [ ] **5E.** Verify CLI argument parsing matches Pascal behavior (flags tolerate preceding or following directory)

---

## Phase 2: Tauri Shell + IPC — ~25-35h

### Checkpoint 6 — Tauri commands + progress + settings + logging

Each command wraps a rust-core function. Frontend communicates via `invoke<...>()`.

**TauriProgress replacement:** Pascal uses `TThread.Queue` / `Synchronize`. Tauri uses its event system.

```rust
#[derive(Serialize)] pub struct ProgressEvent { percent: u8, message: String, phase: String }
// In command implementation: state.emit("progress", ProgressEvent { ... })?;
// Frontend subscribes via listen("progress", ...) and updates JobMonitor store.
// Thumbnail loading: sliding-window ack — frontend sends ack after each batch of 12; backend awaits before next batch.
```

- [ ] **6A.** Set up Tauri v2 project (`cbzmanager-tauri/tauri.conf.json`, main.rs entry point, window creation)
- [ ] **6B. Archive operations commands:**
  - [ ] `list_entries(file: String) -> Result<Vec<String>>`
  - [ ] `read_entry(file: String, name: String) -> Result<Vec<u8>>`
  - [ ] `first_image(file: String) -> Result<Option<Vec<u8>>>`
- [ ] **6C. Service commands** (each wraps rust-core):
  - [ ] `cmd_validate(dir, threads, progress_event)`
  - [ ] `cmd_convert_webp(dir, delete_source, threads, progress_event)`
  - [ ] `cmd_merge(dir, force, chapters?, chapters_per_volume?, progress_event)`
  - [ ] `cmd_cbr_to_cbz(dir, delete_source, threads, progress_event)`
  - [ ] `cmd_scan_comicinfo(dir, threads)`
  - [ ] `cmd_remove_comicinfo(dir, backup, threads)`
- [ ] **6D. Page edit commands** (stateless — frontend store owns model lifecycle):
  - [ ] `page_delete_at`, `page_insert_at`, `page_undo`, `page_save`, `page_revert`
  - [ ] `page_move_up`, `page_move_down`, `page_sort_asc`, `page_sort_desc`, `page_reverse`, `page_renumber`
- [ ] **6E. Directory operations:** `list_directory(dir, filter?) -> Result<Vec<DirEntry>>`
- [ ] **6F. Batch edit command:** `cmd_apply_batch_edit(file, params) -> Result<Vec<PageState>>`
- [ ] **6G. Progress events** — emit from all service commands via `state.emit("progress", event)?`; frontend listens with `listen("progress", ...)`; sliding-window ack for thumbnail batches (batch size 12)
- [ ] **6H. Settings persistence:** `tauri-plugin-store` with `AppSettings { window_width, window_height, max_webp_threads, max_cbr_threads, validate_threads }`; `load_settings()` / `save_settings()` commands
- [ ] **6I. Logging:** `LogObserver` thread-safe buffer published to frontend via Tauri event; CLI mode uses `tracing-subscriber` to stdout

---

## Phase 3: Svelte Frontend — ~60-85h

### Checkpoint 7 — Stores + API layer + types

**Phase 3A.** Data stores (`web/src/stores/*.ts`)

```typescript
// files.ts — file list, selection, thumbnails (Map<number, string> index→dataURL)
// pages.ts — current file's page list + edits (mirrors PageModel)
// progress.ts — job status (active/percent/message/log), epoch counter for stale-result filtering
// settings.ts — app settings via Tauri store plugin
```

**Phase 3C.** Tauri IPC wrapper (`web/src/lib/api.ts`)

```typescript
import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
export const api = { listDirectory, listEntries, readEntry, firstImage, validate, convertWebp, merge, cbrToCbz, pageDeleteAt, pageInsertAt, pageUndo, pageSave, loadSettings, saveSettings };
export function onProgress(callback) { return listen('progress', ...) }
```

**Phase 3D.** Types (`web/src/lib/types.ts`) — mirror Rust structs: `PageState`, `PageChange`, `DirEntry`, `FileValidationResult`, `ConversionResult`, `MergeVolume`, `ProgressEvent`

- [ ] **7A.** Define TypeScript interfaces matching all Rust structs (`types.ts`)
- [ ] **7B.** Create `api.ts` — all invoke() calls matching backend command signatures; progress listener setup/teardown
- [ ] **7C.** Create Svelte stores: `files.ts`, `pages.ts`, `progress.ts`, `settings.ts` with appropriate writable types and helpers

---

### Checkpoint 8 — Core UI components

**Priority order (most complex first, highest risk):**

1. **`MergeDialog.svelte`** (~20h) — Chapter-to-volume merge with sequence builder: zoomable thumbnail grid, chapter navigation, volume addition, undo stack (dedicated writable store with undo middleware)
2. **`PagePreview.svelte`** (~15h) — Page grid with thumbnails, selection, stage bar integration, context menu; handles renumbered page state display
3. **`FileBrowser.svelte`** (~10h) — Left pane: directory with thumbnail list; lazy-load first-page images on hover/scroll; ComicInfo.xml badge painting; batch-selection toolbar
4. **`PageEditor.svelte`** (~12h) — Modal dialog: resize sliders (aspect lock), colour adjust (live preview on first page), split lines (draggable, N→N+1 pieces); encodes via Tauri command
5. **`BatchEdit.svelte`** (~8h) — Uniform parameters for multiple pages: percent resize, colour sliders, split line list + spin controls; header shows "N pages → M pieces"
6. **`JobMonitor.svelte`** (~5h) — Non-modal floating window: title bar, progress bar, elapsed timer (1s tick), scrolling log panel; Alt+F4 guard while job runs
7. **Main layout `routes/+layout.svelte`** (~8h) — Two-pane UI: left `FileBrowser`, right `PagePreview`; keyboard shortcuts (F4, F5, F8, Ctrl+S, Ctrl+A, Space, Del); zoom slider; context menus; toolbar

- [ ] **8A.** Implement `MergeDialog.svelte` with sequence builder and undo middleware
- [ ] **8B.** Implement `PagePreview.svelte` with grid, selection, stage bar integration
- [ ] **8C.** Implement `FileBrowser.svelte` with lazy thumbnail loading and ComicInfo badges
- [ ] **8D.** Implement `PageEditor.svelte` modal (resize + colour + split)
- [ ] **8E.** Implement `BatchEdit.svelte` dialog
      - Wire `apply_batch_edit` through `api.ts` (`BATCH_EDIT` invoke + `cmd_apply_batch_edit` signature parity) and connect the batch UI to selected pages
- [ ] **8F.** Implement `JobMonitor.svelte` non-modal window
- [ ] **8G.** Implement main layout with two-pane UI, keyboard shortcuts, zoom slider, context menus

---

### Checkpoint 9 — Dialog components

7. **`ValidateDialog.svelte`** (~3h) — Results table with per-image pass/fail detail; options panel inline for thread count
8. **`ConvertDialog.svelte`** (~3h) — WebP conversion options + results summary
9. **`CbrDialog.svelte`** (~3h) — CBR→CBZ options + progress/results
10. **`ComicInfoEditor.svelte`** (~4h) — Form with all ComicInfo fields, parse existing or generate new
11. **`PageViewer.svelte`** (~4h) — Full-res page viewer (Space key): center-anchored zoom + wheel pan
12. **`StageBar.svelte`** (~3h) — Unsaved changes bar: Save/Revert buttons; appears when model has pending changes

- [ ] **9A.** Implement `ValidateDialog.svelte` with options panel
- [ ] **9B.** Implement `ConvertDialog.svelte`
- [ ] **9C.** Implement `CbrDialog.svelte`
- [ ] **9D.** Implement `ComicInfoEditor.svelte`
- [ ] **9E.** Implement `PageViewer.svelte` with center-anchored zoom/pan (same math as Pascal)
- [ ] **9F.** Implement `StageBar.svelte`

---

## Phase 4: Polish & Testing — ~25-40h

### Checkpoint 10 — Rust tests + E2E + packaging

#### Rust tests (replacing FPCUnit)

| Pascal test | Rust equivalent | Test type |
|------------|-----------------|-----------|
| `test_uzipeditor.pas` | `rust-core/tests/zip_ops.rs` + integration | ZIP round-trip, entry filtering, image counting |
| `test_uservicevalidate.pas` | `rust-core/tests/validate.rs` | threads=1 vs rayon → identical results |
| `test_userviceconvert.pas` | `rust-core/tests/convert_webp.rs` | threads=1 vs 4 → byte-identical archives |
| `test_uservicemerge.pas` | `rust-core/tests/merge.rs` with `proptest` | Chapter classification, CPV calc, batching vs Pascal outputs |
| `test_uservicecomicinfo.pas` | `rust-core/tests/comicinfo.rs` | threads=1 vs 4 → identical; `cargo insta` XML round-trip snapshot |
| `test_ucomicinfo.pas` | `rust-core/tests/comicinfo_xml.rs` | Parse/generate round-trip (snapshot) |
| `test_upageeditmodel.pas` | `rust-core/tests/page_model.rs` | Delete, reorder, renumber, insert-at, Data precedence |
| `test_uimageedit.pas` | `rust-core/tests/image_edit.rs` | Colour pipeline, resample, split, encode round-trips |
| `test_ubatchedit.pas` | `rust-core/tests/batch_edit.rs` | Param neutrality, resize, colours, split pieces, ext mapping |
| `test_uzipeditor.cbr_*` | `rust-core/tests/cbr_reader.rs` (guarded on libarchive) | Integration test |

**Key patterns:** Determinism (1 thread vs N → byte-identical ZIPs by content); property-based merge testing with random chapter sets; snapshot tests for ComicInfo XML and CLI help text.

- [ ] **10A.** Write `rust-core/tests/zip_ops.rs` — ZIP round-trip, entry filtering, image counting
- [ ] **10B.** Write `rust-core/tests/validate.rs` — threads=1 vs rayon determinism
- [ ] **10C.** Write `rust-core/tests/convert_webp.rs` — threads=1 vs 4 byte-identical archives
- [x] **10D.** Write `rust-core/tests/merge.rs` with `proptest` — random chapter sets vs Pascal reference outputs
- [ ] **10E.** Write `rust-core/tests/comicinfo.rs` + `cargo insta` snapshots for XML round-trip
- [ ] **10F.** Write `rust-core/tests/image_edit.rs` — colour pipeline, resample, split, encode round-trips
- [ ] **10G.** Write `rust-core/tests/page_model.rs` — delete, reorder, renumber, insert-at, Data precedence
- [ ] **10H.** Write `rust-core/tests/batch_edit.rs` — param neutrality, resize, colours, split pieces
- [ ] **10I.** Write `rust-core/tests/cbr_reader.rs` (guarded on libarchive availability)

#### E2E tests (Playwright or tauri-driver)

```
tests/e2e/
├── basic.cy.ts          # Open folder → select file → view pages → Space opens viewer
├── validate.cy.ts       # Select files → validate → check results dialog
├── convert.cy.ts        # Convert to WebP → verify new files created
├── merge.cy.ts          # Merge chapters → sequence preview → generate volumes
├── page_edit.cy.ts      # Open file → edit page (resize + colour) → save → verify changes
├── batch_edit.cy.ts     # Select multiple pages → batch edit → apply
└── settings.cy.ts       # Change settings → restart → verify persistence
```

- [ ] **10J.** Set up Playwright / `tauri-driver` E2E test harness
- [ ] **10K.** Write and pass all 7 E2E scenarios above
- [ ] **10L.** Cross-platform build verification (Linux, Windows, macOS)
- [ ] **10M.** Distribution packaging: deb, rpm, AppImage (Linux); MSI/DMG (Windows/macOS)

---

## Feature Parity Checklist

| Operation | CLI | Tauri GUI | Status |
|-----------|-----|-----------|--------|
| validate [--threads N] | [ ] | [ ] | |
| convert-webp [--delete] [--threads N] | [ ] | [ ] | |
| merge [--delete] [--force] [--chapters] [--chapters-per-volume] | [ ] | [ ] | |
| cbr-to-cbz [--delete] [--threads N] | [ ] | [ ] | |
| remove-comicinfo [--backup] | [ ] | [ ] | |
| Preview pane (CBZ + CBR thumbnails) | — | [ ] | |
| Page editing (delete, reorder, sort, reverse, renumber) | — | [ ] | |
| Stage bar with save/revert | — | [ ] | |
| Page editor modal (resize, colour adjust, split) | — | [ ] | |
| Batch edit dialog | — | [ ] | |
| Job monitor overlay | — | [ ] | |
| Full-res page viewer (Space key) | — | [ ] | |
| ComicInfo.xml view/edit | — | [ ] | |
| Keyboard shortcuts | — | [ ] | |
| Settings persistence | — | [ ] | |

---

## Edge Cases & Failure Modes

| Scenario | Pascal behavior | Rust/Tauri behavior | Notes |
|----------|----------------|--------------------|-------|
| **Corrupt ZIP** | Exception caught, file reported as invalid in validate | `Result::Err(DecodeError)` → surfaced to frontend via command result | Explicit error type mapping |
| **Missing libarchive** | CBR thumbnails disabled; cbr-to-cbz exits 1 | Same: `cbr_reader.rs` functions return Err if FFI handle is None | Graceful degradation at API boundary |
| **Empty CBZ** | Write empty ZIP; merge skips | Write empty ZIP (zip crate handles); merge skips → no volume written | Same as Pascal divergence rule |
| **Concurrent Tauri commands** | Not applicable (single-threaded GUI) | Tauri commands run on Tokio executor — concurrent by default. Services use rayon internally (no contention). | Safe; each command has fresh inputs |
| **Large archive (>100MB)** | All in RAM — can OOM | Same: all in RAM. Should document memory requirements or add streaming for very large files later. | Known limitation, same as Pascal |
| **User switches file mid-operation** | Epoch guard discards stale batches | Frontend epoch counter; all page-edit operations are stateless (input `PageState[]` passed each call). If page edit is active when user closes file → warn before saving. | Page model lives in frontend store, not backend |
| **ComicInfo.xml rename collision** | Handled by strip-then-collect sequence | Strip in `collect_zip_entries` during collection. No collision possible. | Built into design |
| **Split produces empty piece** | Not possible (cut lines validated) | Validate cut lines don't produce degenerate pieces. If detected → error. | UI should validate before sending to backend |
| **WebP encode fails** | Pascal: reports as invalid image | `Result::Err` → reported per-image in validation or conversion results | Non-fatal; other pages continue processing |
| **Merge creates zero-volume CPV** | Fallback to 7 (intentional divergence) | Same logic; document the fallback explicitly. Test case needed. | |

---

## File-to-File Mapping Summary

| Pascal file | Rust module / Svelte component | Effort |
|------------|-------------------------------|--------|
| `uzipcore.pas` | `rust-core/src/zip_ops.rs` | 4h |
| `uzipeditor.pas` | `rust-core/src/zip_ops.rs`, `convert_webp.rs`, `validate.rs`, `merge.rs` | 10h (split across modules) |
| `uarchive.pas` | `rust-core/src/cbr_reader.rs` | 5h |
| `uservicebase.pas` | `rust-core/src/types.rs` + helpers | 2h |
| `uservicevalidate.pas` | `rust-core/src/validate.rs` | 4h |
| `userviceconvert.pas` | `rust-core/src/convert_webp.rs` | 5h |
| `uservicemerge.pas` | `rust-core/src/merge.rs` | 8h (most intricate) |
| `uservicecbr.pas` | `rust-core/src/cbr_convert.rs` | 4h |
| `uservicecomicinfo.pas` | `rust-core/src/comicinfo.rs` | 3h |
| `uimageedit.pas` | `rust-core/src/image_edit.rs` | 5h |
| `uimgutil.pas` | `rust-core/src/image_util.rs` + `webp_decode.rs` | 5h |
| `ubatchedit.pas` | `rust-core/src/batch_edit.rs` | 4h |
| `upageeditmodel.pas` | `rust-core/src/page_model.rs` | 5h |
| `ucomicinfo.pas` | `rust-core/src/comicinfo_xml.rs` | 3h |
| `uwebp.pas` | Covered by `image` crate webp feature + `webp_decode.rs` fallback | Included in image_util |
| `uthreadservice.pas` | Tauri command wrappers + event emission | 2h (built into Phase 2) |
| `ulog.pas` | `rust-core/src/logger.rs` | 2h |
| `uclimode.pas` | `cbzmanager-cli/src/main.rs` | 4h |
| `main.pas`/`.lfm` | `web/src/routes/+layout.svelte` + stores | 8h (Phase 3) |
| All `udlg*.pas`/`.lfm` | `web/src/components/*.svelte` | 30h total across components |

**Total estimated effort: ~180-255 hours** (as stated in TARGET.md, including 20-30% buffer)

---

## Explicit Assumptions & Decisions

1. **Svelte 4 (not 5)** as specified in TARGET.md — Tauri v2 uses `@tauri-apps/api` v2; the Svelte template ships with Svelte 4 by default (if v5 is preferred, adjust accordingly).
2. **Rayon over tokio** for parallel CPU work inside Rust core — rayon's work-stealing is better suited to the fixed-size worker pools that Pascal uses. Tokio powers Tauri's async runtime; rayon handles parallel ops.
3. **`image` crate as primary decoder**, with `webp` crate for encoding (bundles libwebp, no system dependency). If pixel-exact decode parity with Pascal is needed, add FFI-based libwebp in `webp_decode.rs`.
4. **No temp files ever** — same constraint as Pascal. All ZIP/CBR operations use Vec<u8> buffers.
5. **`tauri-plugin-store` for settings** (not `confy`) — more integrated with Tauri, type-safe, cross-IPC.
6. **Feature flags**: CLI build works without Tauri (`cli-only` feature). GUI build includes both. This enables shipping the Rust CLI independently while UI is in development.

---

## Dependency Graph

```
chk 0 (scaffolding) ──→ chk 1 (types) ──→ chk 2 (ZIP ops) ──→ chk 3 (image util)
                                                                 │
                                                   All services (chk 4A-4J)
                                                                 │
                                          chk 5 (CLI binary, needs all of 4)
                                                                 │
                                 chk 6 (Tauri shell — needs 4 complete)
                                                                 │
                    chk 7 (stores + API — can start early with mocks)
                                                                 │
                                    chk 8 ──→ chk 9 (dialogs)
                                                                 │
                                            chk 10 (polish + tests)
```

Phase 3A (chk 7) can start in parallel with Phase 1 using mocked Tauri commands. The TypeScript API layer (`web/src/lib/api.ts`) is the contract — once defined, frontend and backend teams work independently.
