# CLEAN.md — Refactoring roadmap

Audit date: 2025-07-25
Based on analysis of the Lazarus GUI port vs. the Python CLI reference (`porting/cbz_manager/`).

---

## Findings

### 1. Porting completeness (excl. find-similar & delete-by-id): ~55–60%

| Operation | Status | Gap |
|---|---|---|
| **validate** | ~30% | Python checks ZIP integrity (`testzip`) + decodes every image via `PIL.Image.verify()`. Pascal only checks `GetImageCount > 0`. No image-level validation. |
| **convert-webp** | ~80% | Pipeline is correct. **Key difference:** Python uses `ZIP_DEFLATED` (compression 9); Pascal uses *stored* (uncompressed, CRC32=0). Output CBZs are 30–50% larger. Python strips EXIF (`exif=b""`), Pascal does not. |
| **merge** | ~40% | Python has regex-based chapter/special parsing, auto-CPV `(lowest-1)/num_volumes`, two-phase plan+execute, rollback, `--force`, `--chapters`. Pascal has fixed CPV=7 (or manual), no auto-CPV, no rollback, no force. |
| **delete-pages** | ~60% | In-place editing (Gone flag + change tracking) is *more* sophisticated for single-file. Missing: batch operation across all CBZ files in a directory (Python's default mode). |

**Common behaviours** (from `AGENTS.md`):
- ✅ Filter `ComicInfo.xml` — present in `MergeIntoVolume` and `ConvertCBZToWebP`
- ✅ Rename to `page_NNNN.*` — present in save and conversion
- ✅ Backup as `_OLD.cbz` — present
- ❌ `--delete` mode (no backup) — RadioGroup option exists but branch only skips backup, never actually deletes the source

---

### 2. GUI / logic separation: INSUFFICIENT — Smart UI + God Form

**Good:**
- `uzipeditor.pas` — pure logic, zero GUI deps, thread-safe
- `uwebp.pas` — pure library wrapper, thread-safe
- `uimgutil.pas` — mostly thread-safe (only `MakeThumb`/`IntfToBitmap` need GUI)
- `ulog.pas` — no GUI deps
- `uloaderthread.pas` — clean producer-consumer; GUI refs limited to `SyncAddThumbs`

**Bad:**
- **God Form** `TfrmMain` (~1415 lines) — mixes UI layout, event dispatch, business orchestration, and model state (FPages, FChanges, FBaseline)
- **No service layer** — `MnuConvertWebPClick`, `MnuMergeClick`, `MnuRemoveComicInfoClick`, `MnuValidateClick` orchestrate complete operations inline
- **ListView as data source** — `LVFiles.Items` is the authoritative file list, repeated in 5+ places
- **Dialog orchestrates directly** — `TdlgComicInfo.BtnRemoveClick` calls `CollectZipEntries` + `WriteZipFromEntries`

**Desired architecture:**
```
main.pas / dialog (.pas/.lfm)  →  TXXXService.pas  →  uzipeditor.pas / uwebp.pas / uimgutil.pas
(solo UI)                         (orchestrazione)     (low-level operazioni)
```

---

### 3. UI/UX: Functional but rough

**Strengths:**
- Stage bar (save/revert pending changes) — excellent pattern from mockup
- Background thumbnail loading with batch sync (no UI freezes)
- Keyboard shortcuts: F4 (preview), F5 (reload), F8 (validate), Del (delete), Ctrl+S (save)
- Drag-and-drop page reordering
- Zoom slider with debounce
- Dual pane (file list + preview + splitter)
- Multi-access: menu, toolbar, context menu, keyboard

**Weaknesses:**
- Toolbar is icon-only without text labels (some have Hints, not all)
- `StatusProgress` exists but is **never updated** — no progress feedback during WebP conversion, merge, or any batch operation
- "Find Similar" dialog is a skeleton — opens an empty form
- "Delete by ID" dialog does nothing — "logica da completare"
- Merge dialog shows "Vol.X" using hardcoded CPV=7 and doesn't recalculate when CPV changes
- No confirmation dialogs for destructive operations (mitigated by Stage bar)
- `LVFiles` (vsIcon) shows no file metadata (size, page count, date)
- No error feedback to user for most failures — only `SetStatus` on a label; exceptions in `TLoadThread` are silently logged
- Mockup HTML shows a more polished design — current impl is spartan

---

### 4. Code smells

| # | Smell | Location | Impact |
|---|---|---|---|
| 1 | **God Form** | `main.pas` (1415 lines) | Maintainability, testability |
| 2 | **Business logic in event handlers** | `MnuConvertWebPClick`, `MnuMergeClick`, `MnuRemoveComicInfoClick`, etc. | Zero reusability, untestable |
| 3 | **Business logic in dialogs** | `udlgcomicinfo.BtnRemoveClick` calls ZIP ops directly | UI-logic coupling |
| 4 | **DRY violation** | File enumeration from `LVFiles.Items` repeated 5+ times | Bug-prone if UI changes |
| 5 | **Hardcoded magic numbers** | CPV=7 in merge dialog + main, `BatchSize=4` | Rigidity |
| 6 | **Stored ZIP method** | `WriteZipFromEntries` — no compression, CRC32=0 | 30–50% larger output, silent |
| 7 | **Bubble sort** | `MnuPageSortClick` (O(n²)) | Minor, but reveals lack of review |
| 8 | **No Pascal tests** | Zero unit tests for Pascal code | Silent regressions guaranteed |
| 9 | **Fragile change-tracking strings** | `AddChange(ckMoved, 'sort')`, `AddChange(ckMoved, 'inversione')` | Imprecise after multiple ops |
| 10 | **Manual memory management risk** | `TZipEntries` ownership passed around with manual Free | Easy to leak on exception paths |
| 11 | **Hand-written ZIP headers** | `WriteZipFromEntries` — magic bytes `$50 $4B $03 $04` hardcoded | Fragile, could use `TZipFile`/`TZipper` |
| 12 | **Mixed-language comments** | Italian + English scattered throughout | Inconsistency |
| 13 | **Dead / broken code** | `ThumbMouseDown` handles selection for a FlowPanel that was replaced by TListView. `MnuDeleteByIDClick` is a stub. | Confusion, future maintenance |
| 14 | **No interfaces / abstractions** | Direct dependencies everywhere | Impossible to mock in tests |
| 15 | **No progress feedback** | `StatusProgress` declared but never used in long ops | User sees frozen UI |

---

## Priority plan

### Phase 1 — Foundation (safeguard & structure)
1. ✅ **Set up Pascal test framework** (FPCUnit) — 11 tests passing
2. ✅ **Extract service classes** — `TValidateService`, `TConvertService`, `TMergeService`, `TComicInfoService` extracted from event handlers (saved ~170 lines). `TDeletePagesService` excluded per user.
3. ✅ **DRY helper** — `GetFileList` extracted, 4 repetitions replaced.

### Phase 2 — Complete the operations
1. ✅ **Deepen validate** — `ValidateCBZImages` decodes every image entry; dialog shows per-image errors.
2. ✅ **Improve merge** — `CalculateChaptersPerVolume` (matches Python: `(lowest_chapter-1)/num_volumes`), auto-CPV in dialog, force mode implemented.
3. ✅ **Fix convert-webp** — `WriteZipFromEntriesDeflated` added; "Compress (deflate)" checkbox in dialog.
4. ✅ **--delete mode** — Already present via `BackupOld=false`.

### Phase 3 — UI/UX polish
1. ✅ **Wire `TStatusProgress`** — Progress bar + status label updated during WebP conversion and merge operations. Services accept optional `TProgressEvent` callback.
2. ✅ **Toolbar text labels** — Already present (`ShowCaptions=True`, every tool button has a `Caption`).
3. ✅ **Merge dialog CPV recalculation** — Column Vol.X updates in real-time when CPV changes. `RefreshVolumeColumn` added.
4. ✅ **Confirmation dialogs** — Save and revert in the stage bar now show confirmation dialogs before proceeding.
5. ✅ **File metadata** — Page count shown in preview pane (`LblPageCount`). Status bar shows total file count. Tooltip-style detail adequate for current UI.

### Phase 4 — Code quality
1. ✅ **Replace bubble sort** — `MnuPageSortClick` now uses `TStringList.Sort` (O(n log n) quicksort) instead of O(n²) bubble sort.
2. ✅ **Dead code removal** — Removed `ThumbMouseDown`, `SelectRange`, `FSelected`, `FLastClicked`, `LayoutFlowPanel` — stale code from the old FlowPanel layout. ~68 lines removed from `main.pas`.
3. ✅ **Deflate as default** — "Compress (deflate)" checkbox in the convert-webp dialog now defaults to checked, matching Python's `ZIP_DEFLATED` default.
