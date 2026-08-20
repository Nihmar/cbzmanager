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

## Phase 1: Rust Core Library (no GUI) — ~70-95h

### 1A. Project scaffolding (`Cargo.toml`, workspace, feature flags)

**Files to create:**
- `porting/tauri/Cargo.toml` — Workspace with three members: `rust-core/`, `cbzmanager-cli/`, `cbzmanager-tauri/`
- `porting/tauri/rust-core/Cargo.toml` — Core library crate
- `porting/tauri/cbzmanager-cli/Cargo.toml` — CLI binary crate
- `porting/tauri/cbzmanager-tauri/Cargo.toml` — Tauri app crate
- `--no-default-features --features cli-only` for minimal CLI build; `default = ["gui"]` includes Tauri

**Dependency decisions (from TARGET.md):**
| Crate | Version | Use |
|-------|---------|-----|
| `zip` | 0.6 | ZIP read/write, deflate compression |
| `flate2` | — | Deflate backend for zip crate |
| `image` | 0.25 with `default,jpeg,webp,png,bmp,gif,tiff` feature flags | Multi-format decode/encode; GIF encoding requires explicit `gif` flag |
| `webp` | latest | WebP encoding (bundles libwebp, no runtime dependency) |
| `quick-xml` | 0.37 | ComicInfo.xml parse/generate |
| `libloading` | latest | Dynamic libarchive loading |
| `clap` | 4 | CLI argument parsing |
| `tokio` | full | Async runtime for Tauri |
| `tracing` / `tracing-subscriber` | latest | Structured logging |
| `thiserror` | latest | Domain error types |
| `dirs` | latest | App config directory |

**Feature flag design:**
```toml
[features]
default = ["gui"]
gui = ["tauri"]
cli-only = []  # implies no tauri dep, just binary crate
```

### 1B. Shared types (`rust-core/src/types.rs`)

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

### 1C. ZIP operations (`rust-core/src/zip_ops.rs`)

**Replaces:** `uzipcore.pas` + `uzipeditor.pas` (collection/writing parts)

**Functions to implement (Pascal → Rust):**

| Pascal | Rust | Details |
|--------|------|---------|
| `CollectZipEntries` | `collect_zip_entries(path: &Path) -> Result<Vec<ZipEntry>>` | Open ZIP, read each entry into Vec<u8>, skip ComicInfo.xml |
| `WriteZipFromEntries` | `write_zip_from_entries(path: &Path, entries: &[ZipEntry]) -> Result<()>` | Create ZIP (deflate), write entries in order |
| `FreeZipEntries` | — | Rust owns Vec, dropped naturally |
| `StripComicInfo` | Inline in collect | Filter during collection; no separate pass needed |
| `FindComicInfoIndex` | `find_comicinfo_index(entries: &[String]) -> Option<usize>` | Search for ComicInfo.xml by name |
| `FormatPageName` | `format_page_name(index: usize) -> String` | `page_0001.ext` (4-digit zero-padded) |
| `PagePaddingFor` | `page_padding_for(count: usize) -> usize` | Padding = count digits |

**Key invariant:** All operations are RAM-only. `collect_zip_entries` opens the ZIP and reads each entry via compression reader into Vec<u8>. `write_zip_from_entries` creates a fresh ZIP writer (deflate level defaults to 6/ZIP_DEFAULT_COMPRESSION, matching Pascal).

### 1D. Image utilities (`rust-core/src/image_util.rs` + `webp_decode.rs`)

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

### 1E. Validation service (`rust-core/src/validate.rs`)

**Replaces:** `uservicevalidate.pas`

```rust
pub fn validate(path: &Path, threads: usize) -> Result<Vec<FileValidationResult>>;
pub fn validate_deep(path: &Path, threads: usize) -> Result<Vec<FileValidationResult>>;
// FileValidationResult: { path: PathBuf, ok: bool, errors: Vec<ImageCheck> }
// ImageCheck: { filename: String, depth: usize, ok: bool, errors: Vec<String> }
```

**Parallel pool:** Use `rayon` (not tokio threads) for CPU-bound work — same model as Pascal `TValidateWorker`. Rayon's thread pool is more efficient for parallel decode. Worker claims file index under lock → decodes each image → result goes to per-index slot → join assembles in archive order.

### 1F. Convert-webp service (`rust-core/src/convert_webp.rs`)

**Replaces:** `userviceconvert.pas`

```rust
pub fn convert(path: &Path, threads: usize, delete_source: bool) -> Result<ConversionResult>;
// ConversionResult: { converted: Vec<PathBuf>, skipped: Vec<PathBuf> }
```

**Architecture (same as Pascal — deterministic):**
1. Collect all entries into RAM (`collect_zip_entries`)
2. Parallel phase: each worker in rayon pool claims a convertible entry → decodes → encodes to WebP at q75 → checks if smaller than original → stores result in per-slot buffer (None or Vec<u8>)
3. Sequential phase: iterate entries in archive order, compact slots into output entries (filter ComicInfo.xml, renumber as page_NNNN.webp)
4. Write ZIP (`write_zip_from_entries`)
5. Backup or delete source if `delete_source`

### 1G. Merge service (`rust-core/src/merge.rs`)

**Replaces:** `uservicemerge.pas` — the most intricate business logic.

```rust
pub enum MergeConfig {
    Chapters(Vec<usize>),           // --chapters N1,N2,...
    ChaptersPerVolume(usize),       // --chapters-per-volume N
}
pub fn merge(
    dir: &Path,
    force: bool,
    config: MergeConfig,
    chapter_start: u32,
    chapter_end: u32,
    generate_comicinfo: bool,
    threads: usize,
) -> Result<Vec<MergeVolume>>;

pub struct MergeVolume {
    title: String,     // "Title VNNN.cbz"
    output_path: PathBuf,
    chapters: Vec<PathBuf>,  // source chapter paths merged into this volume
    comicinfo_xml: Option<Vec<u8>>, // optional generated ComicInfo.xml
}
```

**Key algorithm decisions (all from TARGET.md — intentional divergences):**
- **Non-image entries dropped**, not renumbered as pages
- **Force below CPV creates single volume** (not skipped)
- **CPV < 1 with volumes present falls back to 7**
- **`.CBZ` glob is case-insensitive** (`*.cbz` + `*.CBZ`)
- **Empty batches produce no volume file** (not empty CBZ)
- **`GenerateComicInfo.xml` per volume** is GUI-only option
- **Multi-series folders merged per series** (one run per series)
- **CPV = `(lowest_chapter - 1) / num_volumes`**, real division, integer result. If == 0, use default 7.

### 1H. ComicInfo XML (`rust-core/src/comicinfo_xml.rs`)

**Replaces:** `ucomicinfo.pas`

```rust
pub struct ComicInfo {
    pub series: Option<String>,
    pub number: Option<String>,
    pub volume: Option<String>,
    pub count: Option<String>,
    pub genre: Option<String>,
    pub summary: Option<String>,
    pub publisher: Option<String>,
    pub imprint: Option<String>,
    pub year: Option<String>,
    pub month: Option<String>,
    pub day: Option<String>,
    pub writers: Vec<String>,
    pub inkers: Vec<String>,
    pub colorists: Vec<String>,
    pub letterers: Vec<String>,
    pub cover_artists: Vec<String>,
    pub tags: Vec<String>,
    pub groups: Vec<String>,
    pub launch_date: Option<String>,
}

pub fn parse_comicinfo_xml(xml: &[u8]) -> Result<ComicInfo>;
pub fn generate_comicinfo_xml(ci: &ComicInfo) -> Vec<u8>;
// Output matches Pascal XML structure exactly for round-trip testing.
```

Use `quick-xml` with a read-write (serialization) approach. Generate sorted element order matching Pascal output for snapshot tests.

### 1I. ComicInfo service (`rust-core/src/comicinfo.rs`)

**Replaces:** `uservicecomicinfo.pas`

```rust
pub enum ComicInfoAction { Scan, Remove }
pub struct ComicInfoResult {
    pub file: PathBuf,
    pub found: bool,
    pub info: Option<ComicInfo>,   // for scan
}
pub fn scan_or_remove(
    dir: &Path,
    action: ComicInfoAction,
    threads: usize,
    backup: bool,
) -> Result<Vec<ComicInfoResult>>;
```

Parallel pool (rayon): each worker claims a `.cbz` index → scans/removes ComicInfo.xml → writes result slot → join assembles. Backup file created before batch starts (same pattern as Pascal).

### 1J. CBR reader (`rust-core/src/cbr_reader.rs`)

**Replaces:** `uarchive.pas`

```rust
// Two-pass scanning (no central directory in RAR):
pub fn cbr_entry_names(path: &Path) -> Result<Vec<String>>;     // names pass
pub fn foreach_cbr_image<F>(path: &Path, callback: F) -> Result<()> where F: FnMut(&str, &[u8]) -> ();
// Collects entries as Vec<u8> (like CollectZipEntries but via libarchive FFI)

// Dynamic loading pattern:
fn load_libarchive() -> Option<LibarchiveHandle>;
```

Same dynamic loading as Pascal's `uarchive.pas`: attempt to load `libarchive.so` on Linux, `libarchive.dll` on Windows. If unavailable, functions return `Err("libarchive not found")`. Two-pass RAR scanning: first pass collects names for alphabetical ranking, second pass reads data.

### 1K. CBR conversion (`rust-core/src/cbr_convert.rs`)

**Replaces:** `uservicecbr.pas`

```rust
pub fn convert_cbr_to_cbz(dir: &Path, threads: usize, delete_source: bool) -> Result<Vec<CbrConversionResult>>;
// CbrConversionResult: { input: PathBuf, output: PathBuf, ok: bool, error: Option<String> }
```

**Parallel unit:** whole file (not per-image), because RAR decompression inside libarchive is single-threaded. Each worker in rayon pool claims a `.cbr` index → reads via `cbr_reader.rs` → writes CBZ → optional source delete. Cap at 4 workers (each holds a full decompressed archive in RAM).

### 1L. Image editing (`rust-core/src/image_edit.rs`)

**Replaces:** `uimageedit.pas`

```rust
pub fn resample_image(img: &DynamicImage, width: u32, height: u32) -> DynamicImage;
  // Box filter, both directions (downscale and upscale). Same as Pascal.

pub fn adjust_colors(img: &DynamicImage, params: &ColorParams) -> DynamicImage;
  // Pipeline: invert → grayscale → sepia → RGB gains → saturation → contrast → brightness → gamma
  // All operations applied sequentially to pixel data.

pub struct CutLine { x1: f64, y1: f64, x2: f64, y2: f64 };  // normalized 0-1 coords
pub fn split_image(img: &DynamicImage, cuts: &[CutLine]) -> Vec<DynamicImage>;
  // N parallel cut lines → N+1 pieces. Same rasterization as Pascal (scanline intersection).
```

**Important:** Image editing operates on decoded `DynamicImage` objects. The pipeline is: decode current state → apply edits → encode back to bytes → store in `PageState::Data`. This matches Pascal's page model.

### 1M. Batch edit (`rust-core/src/batch_edit.rs`)

**Replaces:** `ubatchedit.pas`

```rust
pub struct MultiEditParams {
    pub resize_percent: Option<f64>,
    pub color_adjust: ColorParams,
    pub cut_lines: Vec<CutLine>,  // normalized coords
}
pub fn apply_multi_edit(
    pages: &[PageState],      // current page model state
    params: &MultiEditParams,
) -> Result<Vec<PageState>>;  // edited pages with Data streams
```

Sequential RAM-only pipeline per page. Progress tracking via callback. Same as Pascal `ApplyMultiEditToImage`.

### 1N. Page model (`rust-core/src/page_model.rs`)

**Replaces:** `upageeditmodel.pas`

```rust
pub struct PageState {
    pub orig_name: String,     // original entry name
    pub name: String,          // current/renumbered name (page_NNNN.ext)
    pub data: Option<Vec<u8>>, // edited bytes (if Some, preferred over archive entry)
    pub deleted: bool,         // ckDeleted flag
}

pub struct PageModel {
    pub pages: Vec<PageState>,
    pub baseline: Vec<PageState>,   // open-time snapshot for revert
    pub changes: Vec<Change>,       // linear undo log: ckDeleted | ckMoved | ckEdited
}

impl PageModel {
    pub fn delete_at(index: usize) -> Change;
    pub fn move_up(index: usize) -> Option<Change>;
    pub fn move_down(index: usize) -> Option<Change>;
    pub fn sort_asc() -> Change;
    pub fn sort_desc() -> Change;
    pub fn reverse() -> Change;
    pub fn renumber(&mut self);    // rename all visible pages page_NNNN.ext
    pub fn insert_at(index: usize, pieces: Vec<PageState>) -> Change;  // split result
    pub fn has_changes(&self) -> bool;
    pub fn revert(&mut self);      // reload from baseline
}

// Save logic (TSaveChangesThread replacement):
pub fn save_changes(
    pages: &[PageState],
    output_path: &Path,
    backup_path: &Path,
) -> Result<()>;
  // Encode each page: Data (if Some) wins over archive entry → bytes → ZIP write.
  // Renumbered names applied before writing. Backup created first.
```

**Key behaviors preserved:**
- `ckDeleted` pages excluded from output
- `ckEdited`/`ckMoved` change entries recorded for undo
- Save thread writes ZIP entirely in RAM (no temp files)
- `Data` stream wins over archive entry content (for edited/split pages)
- `OrigName` kept for replace mode; updated only on renumber

### 1O. CLI binary (`cbzmanager/src/main.rs`)

**Replaces:** `uclimode.pas`

```rust
#[derive(clap::Parser)]
#[command(name = "cbzmanager", version, about)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

enum Command {
    Validate { dir: PathBuf, threads: Option<usize> },
    ConvertWebp { dir: PathBuf, delete: bool, threads: Option<usize> },
    Merge { 
        dir: PathBuf, delete: bool, force: bool,
        chapters: Option<String>, chapters_per_volume: Option<usize>,
    },
    CbrToCbz { dir: PathBuf, delete: bool, threads: Option<usize> },
}
```

Same argument structure as Pascal CLI. Flags may precede or follow directory (clap's flexibility). Exit codes: 0 success/benign-no-op, 1 runtime error, 2 usage error. Mutual exclusion of `--chapters` and `--chapters-per-volume` returns 1.

---

## Phase 2: Tauri Shell + IPC — ~25-35h

### 2A. Tauri commands (`cbzmanager-tauri/src/commands/*.rs`)

**Each command wraps a rust-core function:**

```rust
// archive_ops.rs
#[tauri::command]
async fn list_entries(file: String) -> Result<Vec<String>>;
#[tauri::command]
async fn read_entry(file: String, name: String) -> Result<Vec<u8>>;
#[tauri::command]
async fn first_image(file: String) -> Result<Option<Vec<u8>>>;

// validate.rs — delegate to rust-core::validate::validate()
#[tauri::command]
async fn cmd_validate(dir: String, threads: usize, progress: TauriProgress) -> Result<Vec<FileValidationResult>>;

// convert_webp.rs
#[tauri::command]
async fn cmd_convert_webp(dir: String, delete_source: bool, threads: usize, progress: TauriProgress) -> Result<ConversionResult>;

// merge.rs
#[tauri::command]
async fn cmd_merge(dir: String, force: bool, chapters: Option<String>, 
                   chapters_per_volume: Option<usize>, progress: TauriProgress) -> Result<Vec<MergeVolume>>;

// cbr_to_cbz.rs
#[tauri::command]
async fn cmd_cbr_to_cbz(dir: String, delete_source: bool, threads: usize, progress: TauriProgress) -> Result<Vec<CbrConversionResult>>;

// comicinfo.rs
#[tauri::command]
async fn cmd_scan_comicinfo(dir: String, threads: usize) -> Result<Vec<ComicInfoResult>>;
#[tauri::command]
async fn cmd_remove_comicinfo(dir: String, backup: bool, threads: usize) -> Result<()>;

// page_edit.rs (in-memory model + save)
#[tauri::command]
async fn page_delete_at(file: String, index: usize) -> Result<PageChange>;
#[tauri::command]
async fn page_move_up(file: String, index: usize) -> Result<Option<PageChange>>;
#[tauri::command]
async fn page_move_down(file: String, index: usize) -> Result<Option<PageChange>>;
#[tauri::command]
async fn page_sort_asc(file: String) -> Result<PageChange>;
#[tauri::command]
async fn page_sort_desc(file: String) -> Result<PageChange>;
#[tauri::command]
async fn page_reverse(file: String) -> Result<PageChange>;
#[tauri::command]
async fn page_renumber(file: String) -> Result<()>;
#[tauri::command]
async fn page_save(file: String, backup_path: Option<String>) -> Result<()>;
#[tauri::command]
async fn page_revert(file: String) -> Result<()>;
#[tauri::command]
async fn page_insert_at(file: String, index: usize, pieces: Vec<PageState>) -> Result<PageChange>;
#[tauri::command]
async fn page_undo(file: String) -> Result<Option<Change>>;

// directory_ops.rs (file browser)
#[tauri::command]
async fn list_directory(dir: String, filter: Option<String>) -> Result<Vec<DirEntry>>;

// batch_edit.rs
#[tauri::command]
async fn cmd_apply_batch_edit(file: String, params: BatchEditParams) -> Result<Vec<PageState>>;
```

### 2B. Progress reporting via Tauri events

**TauriProgress replacement:** Pascal uses `TThread.Queue` / `Synchronize`. Tauri uses its event system.

```rust
// Define progress events:
#[derive(Serialize)]
pub struct ProgressEvent {
    pub percent: u8,
    pub message: String,
    pub phase: String,  // "collecting", "processing", "saving", etc.
}

// In command implementation:
state.emit("progress", ProgressEvent { percent, message, phase })?;
```

Frontend subscribes via `listen("progress", ...)` and updates the JobMonitor store. For backpressure in the **thumbnail loading path specifically**, use a sliding-window ack pattern: frontend sends ack after processing each batch of 12 thumbnails; backend awaits ack before sending next batch. Other operations stream progress events without flow control (they're informational, not data transfer).

### 2C. Settings persistence (`cbzmanager-tauri/src/settings.rs`)

**Replaces:** `usettings.pas`

Use `tauri-plugin-store` for typed INI-style config:
```rust
#[derive(Serialize, Deserialize)]
pub struct AppSettings {
    pub window_width: u32,
    pub window_height: u32,
    pub thumbnail_cache_size: u32,  // default 128MB equivalent
    pub max_webp_threads: usize,
    pub max_cbr_threads: usize,
    pub validate_threads: usize,
}

pub fn load_settings() -> Result<AppSettings>;
pub fn save_settings(settings: &AppSettings) -> Result<()>;
```

### 2D. Logging (`rust-core/src/logger.rs`)

**Replaces:** `ulog.pas`

```rust
// Structured logging via tracing
#[derive(Serialize)]
pub struct LogEntry { timestamp: String, level: String, message: String };

// Thread-safe buffer published to frontend store.
pub struct LogObserver { entries: Mutex<Vec<LogEntry>>, max_entries: usize };
impl LogObserver {
    pub fn log(&self, entry: LogEntry) { /* push with mutex lock */ }
    pub fn take_entries(&self) -> Vec<LogEntry> { /* drain */ }
}
```

CLI mode uses `tracing-subscriber` to stdout. Tauri mode routes through `LogObserver` → Tauri event → Svelte store.

---

## Phase 3: Svelte Frontend — ~60-85h

### 3A. Data stores (`web/src/stores/*.ts`)

```typescript
// stores/files.ts — file list, selection, thumbnails
export const files = writable<FileItem[]>([]);
export const selectedFile = writable<SelectedFile | null>(null);
export const fileThumbs = Map<number, string>();  // index → dataURL/base64
export const reloadFiles(dir: string): Promise<void>;

// stores/pages.ts — current file's page list + edits (mirrors PageModel)
export const pages = writable<PageState[]>([]);
export const baselinePages = writable<PageState[]>([]);
export const pendingChanges = writable<boolean>(false);

// stores/progress.ts — job monitor state
export const jobStatus = writable<JobStatus>({ active: false, percent: 0, message: '', log: [] });
export const jobIdCounter = writable(0);  // epoch guard for stale-result filtering

// stores/settings.ts — app settings via Tauri store plugin
export const settings = writable<AppSettings>(...);
```

### 3B. Components (`web/src/components/*.svelte`)

**Priority order (most complex first, highest risk):**

1. **`MergeDialog.svelte`** (~20h) — Chapter-to-volume merge with sequence builder: zoomable thumbnail grid, chapter navigation, volume addition, undo stack. Uses a dedicated writable store with undo middleware.
2. **`PagePreview.svelte`** (~15h) — Page grid with thumbnails, selection, stage bar integration, context menu. Handles renumbered page state display.
3. **`PageEditor.svelte`** (~12h) — Modal dialog: resize sliders (aspect lock), colour adjust (live preview on first page), split lines (draggable, N lines → N+1 pieces). Encodes via Tauri command.
4. **`BatchEdit.svelte`** (~8h) — Uniform parameters for multiple pages: percent resize, colour sliders, split line list + spin controls. Header shows "N pages → M pieces" estimate.
5. **`FileBrowser.svelte`** (~10h) — Left pane: directory with thumbnail list. Lazy load first-page images on hover/scroll. ComicInfo.xml badge painting. Batch-selection toolbar (validate, convert, merge, etc.).
6. **`JobMonitor.svelte`** (~5h) — Non-modal floating window: title bar, progress bar, elapsed timer (1s tick), scrolling log panel. Alt+F4 guard while job runs.
7. **`ValidateDialog.svelte`** (~3h) — Results table with per-image pass/fail detail. Options panel inline for thread count selector.
8. **`ConvertDialog.svelte`** (~3h) — WebP conversion options + results summary.
9. **`CbrDialog.svelte`** (~3h) — CBR→CBZ options + progress/results.
10. **`ComicInfoEditor.svelte`** (~4h) — Form with all ComicInfo fields, parse existing or generate new.
11. **`PageViewer.svelte`** (~4h) — Full-res page viewer (Space key): center-anchored zoom + wheel pan, same math as Pascal `CenterAnchorScrollPos`.
12. **`StageBar.svelte`** (~3h) — Unsaved changes bar: Save/Revert buttons, appears when model has pending changes.

### 3C. Tauri IPC wrapper (`web/src/lib/api.ts`)

```typescript
import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';

export const api = {
  // Directory operations
  listDirectory: (dir: string, filter?: string) => 
    invoke<DirEntry[]>('list_directory', { dir, filter }),

  // Archive operations
  listEntries: (file: string) => invoke<string[]>('list_entries', { file }),
  readEntry: (file: string, name: string) => invoke<Uint8Array>('read_entry', { file, name }),
  firstImage: (file: string) => invoke<string | null>('first_image', { file }),
  
  // Services
  validate: (dir: string, threads: number) => 
    invoke<ValidationResult[]>('cmd_validate', { dir, threads }),
  convertWebp: (dir: string, deleteSource: boolean, threads: number) =>
    invoke<ConversionResult>('cmd_convert_webp', { dir, deleteSource, threads }),
  merge: (dir: string, force: boolean, chapters?: string, chaptersPerVolume?: number) =>
    invoke<MergeVolume[]>('cmd_merge', { dir, force, chapters, chapters_per_volume: chaptersPerVolume }),
  cbrToCbz: (dir: string, deleteSource: boolean, threads: number) =>
    invoke<CbrConversionResult[]>('cmd_cbr_to_cbz', { dir, deleteSource, threads }),
  
  // Page editing (stateless — frontend store owns model lifecycle)
  pageDeleteAt: (file: string, index: number) => invoke<PageChange>('page_delete_at', { file, index }),
  pageInsertAt: (file: string, index: number, pieces: PageState[]) => 
    invoke<PageChange>('page_insert_at', { file, index, pieces }),
  pageUndo: (file: string) => invoke<PageChange | null>('page_undo', { file }),
  pageSave: (file: string, backupPath?: string) => invoke<void>('page_save', { file, backup_path: backupPath }),
  
  // Settings
  loadSettings: () => invoke<AppSettings>('load_settings'),
  saveSettings: (settings: AppSettings) => invoke<void>('save_settings', { settings }),
};

// Progress listener — shared across all operations
export function onProgress(callback: (event: ProgressEvent) => void): () => void {
  return listen('progress', (msg) => callback(msg.payload as ProgressEvent));
}
```

### 3D. Types (`web/src/lib/types.ts`)

Mirror the Rust structs with TypeScript interfaces:
```typescript
export interface PageState { origName: string; name: string; data: Uint8Array | null; deleted: boolean }
export interface PageChange { pages: PageState[] }
export interface DirEntry { name: string; isDirectory: boolean }
export interface FileValidationResult { path: string; ok: boolean; errors: ImageCheck[] }
export interface ConversionResult { converted: string[]; skipped: string[] }
export interface MergeVolume { title: string; outputPath: string; chapters: string[] }
export interface ProgressEvent { percent: number; message: string; phase: string }
```

---

## Phase 4: Polish & Testing — ~25-40h

### 4A. Rust tests (replacing FPCUnit)

| Pascal test | Rust equivalent | Test type |
|------------|-----------------|-----------|
| `test_uzipeditor.pas` | `rust-core/tests/zip_ops.rs` + `tests/integration/zip_read_write.rs` | ZIP round-trip, entry filtering, image counting |
| `test_uservicevalidate.pas` | `rust-core/tests/validate.rs` (threads=1 vs rayon → identical results) | Unit + property test |
| `test_userviceconvert.pas` | `rust-core/tests/convert_webp.rs` (threads=1 vs 4 → byte-identical archives by content) | Determinism test |
| `test_uservicemerge.pas` | `rust-core/tests/merge.rs` with `proptest` — chapter classification, CPV calc, batching | Property-based tests vs Pascal reference outputs |
| `test_uservicecomicinfo.pas` | `rust-core/tests/comicinfo.rs` (threads=1 vs 4 → identical archives) + `cargo insta` snapshot for XML round-trip | Determinism + snapshot |
| `test_ucomicinfo.pas` | `rust-core/tests/comicinfo_xml.rs` — parse/generate round-trip | Snapshot test |
| `test_upageeditmodel.pas` | `rust-core/tests/page_model.rs` — delete, reorder, renumber, insert-at, Data precedence | Unit tests |
| `test_uimageedit.pas` | `rust-core/tests/image_edit.rs` — colour pipeline, resample, split, encode round-trips | Unit tests |
| `test_ubatchedit.pas` | `rust-core/tests/batch_edit.rs` — param neutrality, resize, colours, split pieces, ext mapping | Unit + worker test |
| `test_uzipeditor.cbr_*` | `rust-core/tests/cbr_reader.rs` (guarded on libarchive availability) | Integration test |

**Key Rust test patterns:**
- **Determinism**: Run same operation with 1 thread vs N threads → byte-identical output ZIPs (compare entry contents, not timestamps).
- **Property-based merge testing**: Generate random chapter sets → compare classification/batching against known-correct Pascal outputs for the same inputs.
- **Snapshot tests** (`cargo insta`): ComicInfo XML round-trip, CLI help text.

### 4B. E2E tests (Playwright or tauri-driver)

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
| **Merge creates zero-volume CPV** | Fallback to 7 (intentional divergence) | Same logic; document the fallback explicitly. | Test case needed |

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

## Phase Execution Order & Dependencies

```
Phase 1A (scaffolding) ──→ Phase 1B (types) ──→ Phase 1C-1N (core modules, can parallelize)
                                                    │
                                            Phase 1O (CLI binary, depends on all services)
                                                    │
                                    Phase 2 (Tauri shell — depends on Phase 1 complete)
                                                    │
                                    Phase 3 (Svelte frontend — mock commands possible early)
                                                    │
                                    Phase 4 (Polish + E2E tests — depends on Phase 3)
```

Phase 3 can start in parallel with Phase 1 using mocked Tauri commands. The TypeScript API layer (`web/src/lib/api.ts`) is the contract — once defined, frontend and backend teams work independently.
