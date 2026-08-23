# Tauri vs Lazarus -- Complete Feature Gap & Bug List

Lazarus app is the ground truth. Every item references the Tauri file+line where
the gap lives, and the Lazarus file+line for expected behaviour.

---

## 1. Command-layer bugs (options silently dropped or hardcoded)

### 1.1 CBR->CBZ: delete_source accepted but never passed

- **Tauri**: `src-tauri/src/commands/cbr_to_cbz.rs:17` -- param `_delete_source: bool`
- **Tauri**: `src-tauri/src/commands/cbr_to_cbz.rs:24-25` -- comment says it is ignored
- **Tauri**: `src-tauri/src/commands/cbr_to_cbz.rs:66-72` -- `convert_cbr_to_cbz_with_progress` called without `delete_source`
- **Rust-core**: `rust-core/src/cbr_convert.rs:41` -- `process_cbr` accepts `delete_source`
- **Rust-core**: `rust-core/src/cbr_convert.rs:179,246` -- always called with `false`
- **Lazarus**: `src/uservicecbr.pas` -- `Options.DeleteSource` threaded through to workers
- **Fix**: Rename to `delete_source`, pass through to `convert_cbr_to_cbz_with_progress` and into `process_cbr`.

### 1.2 CBR->CBZ: skip_existing hardcoded false

- **Tauri**: `src-tauri/src/commands/cbr_to_cbz.rs:70` -- `false, // skip_existing`
- **Rust-core**: `rust-core/src/cbr_convert.rs:168` -- `_skip_existing: bool` accepted but never checked
- **Lazarus**: `src/udlgcbr.pas` -- `CbSkipExisting: TCheckBox` (default checked)
- **Fix**: Add `skip_existing` param, pass through, implement check (skip if target `.cbz` exists).

### 1.3 CBR->CBZ: no thread cap at MAX_CBR_THREADS (4)

- **Tauri**: `src-tauri/src/commands/cbr_to_cbz.rs:33` -- caps at `cpu_count` only
- **Rust-core**: `rust-core/src/types.rs:23` -- `MAX_CBR_THREADS = 4` exists but is never used
- **Lazarus**: `src/uservicebase.pas:43` -- `MAX_CBR_CONVERT_THREADS = 4`
- **Lazarus**: `src/uservicecbr.pas:246-247` -- `Min(OnlineCpuCount, MAX_CBR_CONVERT_THREADS)`
- **Fix**: Cap at `min(cpu_count, MAX_CBR_THREADS)`.

### 1.4 ComicInfo remove: no thread cap

- **Tauri**: `src-tauri/src/commands/comicinfo.rs:94` -- `threads.unwrap_or(0).max(1)` -- no cap
- **Lazarus**: `src/uservicecomicinfo.pas:316-317` -- `Min(OnlineCpuCount, MAX_CBR_CONVERT_THREADS)` (cap 4)
- **Fix**: Cap at `min(cpu_count, MAX_CBR_THREADS)`.
- **Resolved** (2026-08-24): `cmd_remove_comicinfo` now caps `actual_threads` at `rust_core::types::MAX_CBR_THREADS` before calling `remove_with_progress`. Matches Pascal.

### 1.5 Convert-WebP: quality hardcoded to 0 (q75 default)

- **Tauri**: `src-tauri/src/commands/convert_webp.rs:74` -- `0,` (quality arg)
- **Tauri**: `src-tauri/src/commands/convert_webp.rs:73` -- comment: "Tauri GUI will expose this as a knob"
- **Lazarus**: `src/udlgwebp.pas:15` -- `TrackQuality: TTrackBar` range 30-100, default 75
- **Fix**: Add `quality: Option<u32>` to `cmd_convert_webp`, pass through.

### 1.6 Convert-WebP: skip_existing not exposed

- **Tauri**: `src-tauri/src/commands/convert_webp.rs:14` -- no `skip_existing` param
- **Rust-core**: `rust-core/src/convert_webp.rs:206` -- always converts (per-image only)
- **Lazarus**: `src/udlgwebp.pas:18` -- `CbSkipExistingWebP: TCheckBox` (default checked)
- **Lazarus**: `src/userviceconvert.pas` -- `Options.SkipExistingWebP` checked before conversion
- **Fix**: Add `skip_existing: Option<bool>` to the command.

### 1.7 Convert-WebP: remove_comicinfo not user-configurable

- **Tauri**: `src-tauri/src/commands/convert_webp.rs:14` -- no such param
- **Rust-core**: `rust-core/src/convert_webp.rs:61` -- always strips ComicInfo (hardcoded)
- **Lazarus**: `src/udlgwebp.pas:19` -- `CbRemoveComicInfo: TCheckBox` (default on, can disable)
- **Impact**: Minor -- default matches, but user cannot keep ComicInfo.
- **Fix**: Add `remove_comicinfo: Option<bool>`, conditionally filter.
- **Resolved** (2026-08-24): `cmd_convert_webp` accepts `quality`/`skip_existing`/`remove_comicinfo`/`renumber`/`replace_only_if_smaller` and builds a `ConvertOptions` struct (with sensible default fallbacks) forwarded to `convert_webp_with_progress`; rust-core already threaded these knobs through the pipeline.

### 1.8 Convert-WebP: renumber not user-configurable

- **Rust-core**: `rust-core/src/convert_webp.rs:104-136` -- always renumbers sequentially
- **Lazarus**: `src/udlgwebp.pas:20` -- `CbRenumber: TCheckBox` (default on)
- **Impact**: Minor -- default matches.
- **Fix**: Add `renumber: Option<bool>`, skip renumbering when false.

### 1.9 Convert-WebP: replace_only_if_smaller not configurable

- **Rust-core**: `rust-core/src/convert_webp.rs:176` -- always checks `webp_data.len() < original_size`
- **Lazarus**: `src/udlgwebp.pas:17` -- `CbReplaceOnlySmaller: TCheckBox` (default checked)
- **Impact**: Minor -- default matches.
- **Fix**: Add param, skip size check when false.

### 1.10 Merge: chapter_start / chapter_end missing

- **Tauri**: `src-tauri/src/commands/merge.rs:20-27` -- no chapter range params
- **Rust-core**: `rust-core/src/merge.rs:255-261` -- `merge_chapters` has no range params
- **Lazarus**: `src/udlgmerge.pas:24-25` -- `EditChapterStart` / `EditChapterEnd` spin edits
- **Lazarus**: `src/uservicemerge.pas` -- `TMergeOptions.ChapterStart/ChapterEnd` filters chapters
- **Fix**: Add `chapter_start: Option<usize>` and `chapter_end: Option<usize>` to command and rust-core.
- **Resolved** (2026-08-24): `merge_chapters` / `merge_chapters_with_progress` now take `chapter_start`/`chapter_end` and filter the parsed chapters via `filter_chapter_range` (inclusive, both bounds optional = unbounded) before planning. CLI passes `None`/`None` (full range). Covered by `merge_respects_chapter_range` in `rust-core/tests/merge.rs`.

### 1.11 Merge: generate_comicinfo not passed

- **Tauri**: `src-tauri/src/commands/merge.rs:72-85` -- no `generate_comicinfo` param
- **Rust-core**: `rust-core/src/types.rs:132` -- `MergeVolume.comicinfo_xml` exists but never populated
- **Lazarus**: `src/udlgmerge.pas:20` -- `CbGenerateComicInfo: TCheckBox` (default checked)
- **Lazarus**: `src/uservicemerge.pas` -- `Options.GenerateComicInfo` triggers per-volume ComicInfo
- **Fix**: Add `generate_comicinfo: Option<bool>` to command; generate and embed ComicInfo.xml in each volume.
- **Resolved** (2026-08-24): `merge_cbz_files` now takes a `generate_comicinfo` flag and, when set, prepends a generated `ComicInfo.xml` (`default_comicinfo()` with Title/Volume/Count/PageCount filled from the volume) before writing. Threaded through both merge entry points + `cmd_merge`. Covered by `merge_generates_comicinfo_per_volume` in `rust-core/tests/merge.rs`.

### 1.12 Merge: force partially implemented

- **Tauri**: `src-tauri/src/commands/merge.rs:22` -- `force: bool` param accepted
- **Rust-core**: `rust-core/src/merge.rs:258` -- `_force: bool` (underscore prefix, unused)
- **Lazarus**: `src/uservicemerge.pas` -- force absorbs remainder chapters into the last volume
- **Fix**: Implement force logic in `merge_chapters` (absorb leftover chapters into final volume).
- **Resolved** (2026-08-22): `plan_series()` now centralizes the force/chapters-list/manual-CPV Phase-1 planning; both `merge_chapters` and `merge_chapters_with_progress` delegate to it. `force` absorbs leftover chapters into the last volume when batches are laid out (mirrors `chapters_per_volume_int` + `force`). Covered by new tests in `rust-core/tests/merge.rs`.

### 1.13 Merge: chapters list (specific chapters) partially implemented

- **Tauri**: `src-tauri/src/commands/merge.rs:23` -- `chapters: Option<String>` accepted
- **Rust-core**: `rust-core/src/merge.rs:259` -- `_chapters_list: Option<Vec<usize>>` (unused)
- **Lazarus**: `src/udlgmerge.pas` -- chapter list allows selecting specific chapters to merge
- **Fix**: Implement specific-chapters merge in rust-core.
- **Resolved** (2026-08-22): `chapters_list` now pins exact per-volume chapter counts and drives the volume count directly via `plan_series()` (`num_new_volumes = len(list)`), mirroring Python; skipped when the requested sum exceeds available chapters. Covered by new tests in `rust-core/tests/merge.rs`.

### 1.14 Merge: chapters_per_volume partially implemented

- **Tauri**: `src-tauri/src/commands/merge.rs:24` -- `chapters_per_volume: Option<u32>` accepted
- **Rust-core**: `rust-core/src/merge.rs:260` -- `_chapters_per_volume: Option<usize>` (unused)
- **Lazarus**: `src/udlgmerge.pas:26` -- `EditCPV` spin edit + `CbManualCPV` checkbox
- **Lazarus**: `src/uservicemerge.pas` -- manual CPV overrides auto-calculated float
- **Fix**: Implement manual CPV override in rust-core.
- **Resolved** (2026-08-22): `cpv_override` now fixes chapters-per-volume directly via `plan_series()` when set, overriding the auto-calculated `(lowest_chapter-1)/num_volumes`; both functions delegate to the helper. CLI/tauri callers widen the param to `Option<f64>`. Covered by new tests in `rust-core/tests/merge.rs`.

### 1.15 Batch edit: sequential, not parallel

- **Tauri**: `src-tauri/src/commands/batch_edit.rs:102` -- `for (idx, entry) in entries.iter().enumerate()`
- **Lazarus**: `src/ubatchedit.pas` -- `TMultiEditWorker` runs on background thread
- **Rust-core**: `rust-core/src/batch_edit.rs` -- sequential processing
- **Fix**: Use `rayon` parallel iterator for the page decode-edit-encode pipeline.
- **Resolved** (2026-08-22): added `apply_batch_to_inputs(inputs, params)` in `rust-core/src/batch_edit.rs`, a rayon `.par_iter().enumerate()` fan-out that decodes → resize/colour/split → encodes one page per worker and collects results in index order. Undecodable/failed pages yield empty pieces (caller keeps the original). Output is byte-identical for any thread count (per-page encode is deterministic; slots never share state). The Tauri command (`apply_batch_edit`) was refactored to call it; `rust-core/tests/batch_edit.rs` asserts parallel output matches a sequential reference and preserves indices.

---

## 2. Missing Tauri commands (features in Lazarus with no command at all)

### 2.1 Page move up / move down

- **Lazarus**: `src/main.pas:2397-2426` -- `MnuPageMoveUpClick` / `MnuPageMoveDownClick`
- **Lazarus**: `src/upageeditmodel.pas` -- `PageMoveUp` / `PageMoveDown` (skip Gone neighbours)
- **Rust-core**: `rust-core/src/page_model.rs:142,156` -- `move_up` / `move_down` implemented
- **Tauri**: `src-tauri/src/lib.rs:15-38` -- no `page_move_up` / `page_move_down` commands
- **Fix**: Add `page_move_up(pages, index)` and `page_move_down(pages, index)` Tauri commands.
- **Resolved** (2026-08-24): added `page_move_up` / `page_move_down` to `page_edit.rs`, registered in `lib.rs`; they build a `PageModel`, apply the swap, and return the reordered (base64) page list.

### 2.2 Page move to start / move to end

- **Lazarus**: `src/main.pas:2434-2456` -- `MnuPageMoveStartClick` / `MnuPageMoveEndClick`
- **Lazarus**: `src/upageeditmodel.pas` -- `PageMoveToStart` / `PageMoveToEnd`
- **Rust-core**: `rust-core/src/page_model.rs` -- not implemented (only move_up/move_down)
- **Fix**: Add `move_to_start` / `move_to_end` to rust-core and expose as commands.
- **Resolved** (2026-08-24): added `PageModel::move_to_start` / `move_to_end` (operating on visible, non-deleted pages) plus Tauri commands `page_move_to_start` / `page_move_to_end`, registered in `lib.rs`. See also 2.7.

### 2.3 Page sort (alphabetical) / reverse

- **Lazarus**: `src/main.pas:2466-2487` -- `MnuPageSortClick` / `MnuPageReverseClick`
- **Lazarus**: `src/upageeditmodel.pas` -- `PageSort` / `PageReverse`
- **Rust-core**: `rust-core/src/page_model.rs:170,182,194` -- `sort_asc` / `sort_desc` / `reverse` implemented
- **Tauri**: `src-tauri/src/lib.rs:15-38` -- no sort/reverse commands
- **Fix**: Add `page_sort(pages)` and `page_reverse(pages)` commands.
- **Resolved** (2026-08-24): added `page_sort_asc` / `page_sort_desc` / `page_reverse`, registered in `lib.rs`.

### 2.4 Page renumber

- **Lazarus**: `src/main.pas:2498-2508` -- `MnuPageRenumberClick`
- **Lazarus**: `src/upageeditmodel.pas` -- `PageRenumber` (sequential `page_NNNN.*`)
- **Rust-core**: `rust-core/src/page_model.rs:217` -- `renumber` implemented
- **Tauri**: no renumber command
- **Fix**: Add `page_renumber(pages)` command.
- **Resolved** (2026-08-24): added `page_renumber`, registered in `lib.rs`.

### 2.5 Page undo

- **Lazarus**: `src/upageeditmodel.pas` -- undo stack via `TChanges` array
- **Rust-core**: `rust-core/src/page_model.rs:206` -- `undo` implemented
- **Tauri**: no undo command
- **Fix**: Add `page_undo(pages, changes)` command.
- **Resolved** (2026-08-24): added `page_undo`, registered in `lib.rs`.

### 2.6 Page insert front / insert at

- **Lazarus**: `src/main.pas:2522-2580` -- `MnuPageAddFrontClick` (insert image as page 0)
- **Lazarus**: `src/upageeditmodel.pas` -- `PageInsertFront` / `PageInsertAt`
- **Rust-core**: `rust-core/src/page_model.rs` -- `insert_at` implemented
- **Tauri**: no insert commands
- **Fix**: Add `page_insert_front(pages, file_data, ext)` and `page_insert_at(pages, index, file_data, ext)`.
- **Resolved** (2026-08-24): added `page_insert_front` / `page_insert_at`, registered in `lib.rs`.

### 2.7 Page drag-drop reorder

- **Lazarus**: `src/upageeditmodel.pas` -- `PageDragDrop(APages, AChanges, AFromIdx, AToIdx)`
- **Rust-core**: not implemented
- **Fix**: Add `drag_drop` to rust-core and expose as command.
- **Resolved** (2026-08-24): added `PageModel::drag_drop(from, to)` (reorders visible pages, snapping past deleted slots) plus Tauri command `page_drag_drop`, registered in `lib.rs`. Covered by `drag_drop_moves_between_visible_slots` / `drag_drop_snap_past_deleted_slots` / `undo_reverts_drag_drop` in `rust-core/tests/page_model.rs`.

### 2.8 Single-page editor

- **Lazarus**: `src/udlgpageeditor.pas:64` -- `TdlgPageEditor` modal editor
- **Lazarus**: `src/udlgpageeditor.pas:459-482` -- Resize with absolute px + aspect lock
- **Lazarus**: `src/udlgpageeditor.pas:525-543` -- Colour pipeline (full AdjustColors)
- **Lazarus**: `src/udlgpageeditor.pas:726-767` -- Split with draggable cut lines
- **Lazarus**: `src/main.pas:1261-1270` -- `MnuPageEditClick` opens editor
- **Tauri**: `web/src/components/PageViewer.svelte` -- no edit button or entry point
- **Fix**: Create `PageEditor.svelte` component + `page_edit_single` Tauri command.

### 2.9 Delete pages by range dialog

- **Lazarus**: `src/udlgrows.pas:115-167` -- `ParseRangeString` ("1,4,7-10,15")
- **Lazarus**: `src/udlgrows.pas:59-61` -- batch-all, delete-permanently, renumber options
- **Lazarus**: `src/main.pas` -- `MnuDeleteRowsClick` opens dialog
- **Tauri**: no equivalent -- only Delete key on selected pages
- **Fix**: Create `DeleteRowsDialog.svelte` + wire to a command.

---

## 3. Missing Svelte UI components

### 3.1 No zoom slider on thumbnail grid

- **Lazarus**: `src/main.pas:187` -- `ZoomScroll: TTrackBar` (Min=48, Max=320, Default=128)
- **Lazarus**: `src/main.pas:804-809` -- `SetupZoomScroll`
- **Lazarus**: `src/main.pas:951-956` -- `ZoomScrollChange` triggers debounce rebuild
- **Lazarus**: `src/main.pas:901-911` -- `TimerDebounceZoomTimer` calls `RebuildThumbs`
- **Tauri**: `web/src/App.svelte` -- no zoom control; fixed 128px thumbnails
- **Fix**: Add a range input bound to thumbnail size, debounce rebuild.
- **Resolved** (2026-08-24): added shared `stores/thumbnail.ts` (`thumbnailSize`, default 128, clamped 48-320) and a zoom range input in the App toolbar. `FileBrowser` scales its thumbs with the slider; `PagePreview` card width is now `clamp(80, thumbnailSize, 260)` via an inline style, so both panes respond to the zoom (matching Lazarus ZoomScroll). DOM reflow replaces the Pascal IntfImage rebuild, so a debounce timer is unnecessary.

### 3.2 No context menus (right-click)

- **Lazarus**: `src/main.pas` -- popup menus on both LVFiles and LVPages
- **Lazarus**: `src/main.pas:2372-2580` -- page context menu: Edit, Delete, Move, Sort, Insert
- **Tauri**: `web/src/components/PagePreview.svelte` -- no contextmenu handler
- **Tauri**: `web/src/components/FileBrowser.svelte` -- no contextmenu handler
- **Fix**: Add `on:contextmenu` handlers with dropdown menus.
- **Partially resolved** (2026-08-24): `PagePreview` now has a right-click menu (Move up/down, Move to top/bottom) wired to the `page_move_*` commands via `api.ts`. The file-browse pane context menu still awaits FileBrowser.

### 3.3 No menu bar

- **Lazarus**: `src/main.pas:127` -- `MainMenu: TMainMenu`
- **Lazarus**: `src/main.lfm` -- full menu structure (File/Archive/Pages/View)
- **Tauri**: no menu bar in any component
- **Fix**: Add a `<nav>` menu bar or use Tauri's native menu API.

### 3.4 No ComicInfo editor (view/edit/create)

- **Lazarus**: `src/udlgcomicinfoeditor.pas:12` -- `TdlgComicInfoEditor`
- **Lazarus**: `src/udlgcomicinfoeditor.pas:21,43,65,81` -- 4 tabs (General/Story/Credits/Publishing)
- **Lazarus**: `src/udlgcomicinfoeditor.pas:133-201` -- `DataToUI` populates ~30 fields
- **Lazarus**: `src/udlgcomicinfoeditor.pas:203-268` -- `UIToData` reads back
- **Tauri**: `web/src/components/ComicInfoDialog.svelte:117-126` -- raw XML view only
- **Fix**: Create `ComicInfoEditor.svelte` with form fields matching the 4-tab layout.

### 3.5 No sequence builder

- **Lazarus**: `src/udlgseqbuilder.pas` -- interactive volume assignment with thumbnails, undo, front-consumption
- **Lazarus**: `src/udlgmerge.pas:16` -- `BtnBuildSeq` opens sequence builder
- **Tauri**: `web/src/components/MergeDialog.svelte` -- text-only, no visual builder
- **Fix**: Create `SequenceBuilder.svelte` with grid-based chapter assignment.

### 3.6 No live preview in batch edit

- **Lazarus**: `src/udlgbatchedit.pas` -- debounced timer previews first page with current sliders
- **Lazarus**: `src/udlgbatchedit.pas` -- `RefreshPreviewCopy` / `TimerPreviewTimer`
- **Tauri**: `web/src/components/BatchEdit.svelte` -- shows result grid after apply, no live preview
- **Fix**: Add debounced preview that decodes first page and applies current params.
- **Resolved** (2026-08-24): on open, BatchEdit reads the archive entry listing via `listEntries` for the header count, then fetches the first entry's bytes once (`readEntryBytes`) and builds an object URL. Colour/resize changes are applied with CSS `filter`/`scale` (no re-read), so dragging sliders is instant.

### 3.7 No page count header in batch edit

- **Lazarus**: `src/udlgbatchedit.pas` -- header shows "N pages -> M pieces"
- **Tauri**: `web/src/components/BatchEdit.svelte` -- no dynamic header
- **Fix**: Add header showing input/output page counts based on cut lines.
- **Resolved** (2026-08-24): reactive `applyHeader` shows `Apply to N page(s)` when there are no split lines, else `Apply to N pages -> M pieces` with `M = N * (cutLines.length + 1)` -- exactly the Lazarus `RefreshHeader` formula (`udlgbatchedit.pas:204-216`).

### 3.8 No page editor entry point in PageViewer

- **Lazarus**: `src/udlgpageview.pas` -- floating window has Edit button
- **Lazarus**: `src/main.pas:1261-1270` -- opens `TdlgPageEditor`
- **Tauri**: `web/src/components/PageViewer.svelte` -- no Edit button
- **Fix**: Add Edit button to PageViewer toolbar.

### 3.9 No drag-and-drop page reordering

- **Lazarus**: `src/upageeditmodel.pas` -- `PageDragDrop` handles from-to reordering
- **Lazarus**: `src/main.pas` -- `LVPages` has drag-drop support
- **Tauri**: `web/src/components/PagePreview.svelte` -- static grid, no drag
- **Fix**: Add HTML5 drag-and-drop or a sortable library.
- **Resolved** (2026-08-24): page cards are now `draggable`; drop targets compute the visible-slot indices and call `page_drag_drop` (via `api.ts`) to reorder, updating the store + marking changes. The in-memory reorder matches the Lazarus `PageDragDrop` visible-slot semantics.

### 3.10 No multi-select on pages

- **Lazarus**: `src/main.pas:580-587` -- `Ctrl+A` selects all pages
- **Tauri**: `web/src/App.svelte:102` -- comment: "no multi-select model yet -- deferred"
- **Fix**: Add selection model to PagePreview (shift-click range, ctrl-click toggle).

### 3.11 No subdirectory navigation

- **Lazarus**: `src/main.pas` -- double-click enters subdirectory, breadcrumb navigation
- **Tauri**: `web/src/components/FileBrowser.svelte` -- flat file list only
- **Tauri**: `web/src/App.svelte:129-136` -- directory path typed manually
- **Fix**: Handle `is_dir` entries in FileBrowser, navigate on double-click.
- **Resolved** (2026-08-24): FileBrowser rows are now clickable for files and double-clickable to enter folders (📁 indicator; single-click is ignored on dirs so it never tries a `pageLoad` on a path). App keeps an ordered `history` breadcrumb trail plus an in-memory `dirCache`; `enterSubdir` pushes a level and lists the child, while clicking a breadcrumb chip `jumpToLevel`s back to that cached listing. Mirrors the Lazarus double-click-enters-subdirectory + breadcrumb flow.

### 3.12 No native file/folder picker

- **Lazarus**: `src/main.pas` -- uses Lazarus directory dialog
- **Tauri**: `web/src/App.svelte:129-136` -- text input for directory path
- **Fix**: Use Tauri's `dialog` plugin for native folder picker.

---

## 4. Settings and persistence gaps

### 4.1 Settings commands exist but are never wired to dialogs

- **Tauri**: `src-tauri/src/commands/settings.rs:27-60` -- `load_settings` / `save_settings` commands
- **Tauri**: `src-tauri/src/lib.rs:23-24` -- registered in invoke handler
- **Tauri**: `web/src/components/ConvertDialog.svelte` -- never calls load_settings or save_settings
- **Tauri**: `web/src/components/CbrDialog.svelte` -- never calls load_settings or save_settings
- **Tauri**: `web/src/components/ValidateDialog.svelte` -- never calls load_settings or save_settings
- **Lazarus**: `src/usettings.pas` -- `AppSettings: TIniFile` persists thread counts between dialog opens
- **Lazarus**: `src/udlgbase.pas` -- `TSettingsDialog` base class auto-loads/saves on open/ok
- **Fix**: Wire settings persistence: load on dialog open, save on confirm.

### 4.2 Settings struct missing fields

- **Tauri**: `src-tauri/src/commands/settings.rs` -- `AppSettings` has only `max_webp_threads`, `max_cbr_threads`, `validate_threads`, `window_width`, `window_height`
- **Lazarus**: `src/udlgwebp.pas` -- INI keys: `WebP/Quality`, `WebP/ReplaceOnlyIfSmaller`, `WebP/SkipExistingWebP`, `WebP/RemoveComicInfo`, `WebP/Renumber`, `WebP/BackupMode`
- **Lazarus**: `src/udlgmerge.pas` -- INI keys: `Merge/CPV`, `Merge/ManualCPV`, `Merge/GenerateComicInfo`
- **Lazarus**: `src/udlgcbr.pas` -- INI keys: `CBR/SkipExisting`, `CBR/DeleteSource`
- **Lazarus**: `src/udlgcomicinfo.pas` -- INI keys: `RemoveComicInfo/Backup`
- **Fix**: Extend `AppSettings` with all dialog-specific options.

---

## 5. Security and production concerns

### 5.1 CSP set to null

- **Tauri**: `src-tauri/tauri.conf.json:24` -- `"csp": null`
- **Fix**: Set a proper Content Security Policy for production builds.

### 5.2 No E2E tests

- **Tauri**: No Playwright/tauri-driver tests, no frontend unit tests
- **Lazarus**: 23 FPCUnit test files covering all operations
- **Rust-core**: 10 integration test files (backend only)
- **Fix**: Add E2E tests for critical paths.

### 5.3 No packaging/CI scripts

- **Tauri**: No Makefile targets, no GitHub Actions workflows, no deb/rpm/AppImage config
- **Lazarus**: `Makefile` with build/test/install-man targets
- **Fix**: Add Tauri build scripts and CI pipeline.

---

## 6. Behavioral differences in shared features

### 6.1 Thumbnail loading strategy

- **Lazarus**: `src/uloaderthread.pas:215` -- `BatchSize = 12` sliding window with backpressure
- **Lazarus**: `src/uloaderthread.pas:334-340` -- epoch-based stale batch protection
- **Tauri**: `web/src/components/PagePreview.svelte` -- all pages loaded at once as base64
- **Impact**: Memory spike on large CBZ files; potential stale data on rapid file switching.
- **Fix**: Implement sliding-window loading with epoch guard.

### 6.2 PageViewer zoom model

- **Lazarus**: `src/uimgutil.pas` -- `CenterAnchorScrollPos` for center-anchored zoom
- **Lazarus**: `src/udlgpageview.pas` -- Ctrl+wheel zoom (1.0-5.0), wheel pan, Shift+wheel horizontal pan
- **Tauri**: `web/src/components/PageViewer.svelte:29-33` -- simple scale factor, pointer-drag pan only
- **Fix**: Implement center-anchored zoom and shift+wheel horizontal pan.

### 6.3 CBR preview is read-only

- **Lazarus**: `src/main.pas` -- `IsReadOnlyPreview` disables page operations for CBR files
- **Tauri**: Not explicitly handled -- batch operations may attempt to modify CBR files
- **Fix**: Detect CBR source and disable page editing operations.
