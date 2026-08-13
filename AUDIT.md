# Code & UI Audit

Full-repo audit (layouts, main-form logic, archive operations, model/image/thread units), 2026-08-13. Findings are ordered by severity. The two CRITICAL/HIGH claims marked (verified) were confirmed by reading the exact code paths; the rest come from the deep scans that produced this report.

---

## 1. UI problems (overlapping controls)

| Form | Problem |
|---|---|
| `src/main.lfm` — PanelStageBar | alLeft stack (LblStageMsg 240 + CbBackup 111 = 351) + alRight buttons (156) = **507px > 480px panel** → CbBackup overlaps BtnStageSave by ~11–15px when the stage message is long. `ShapeStageDot` (0,0,10,10) also overlaps `LblStageMsg`'s corner — no space is reserved for the dot. |
| `src/udlgpageeditor.lfm` — TabColors | Trackbars are 40px tall on a 34px pitch: **6 vertical overlaps** between consecutive sliders; `TrackBlue` (bottom 252) overlaps the Grayscale/Sepia/Invert checkbox row (3–58×6px). |
| `src/udlgbatchedit.lfm` — TabColors | Same 6 track-pair overlaps + TrackBlue vs checkboxes (10×6, 80×6, 43×6); row labels are 300px wide and run over the trackbars and the value labels. |
| `src/udlgwebp.lfm`, `src/udlgcomicinfo.lfm` | `LblThreads: TLabel` objects exist in the .lfm but have no published field in the .pas (runtime-benign; IDE drift — `udlgcbr.pas`/`udlgvalidateopts.pas` do declare theirs). |
| Minor | `src/udlgrows.lfm` leftover `Text = 'EditRanges'` (cleared at runtime); `src/udlgbase.lfm` `biMaximize` on `bsDialog` (ignored); `src/ufrmjobmonitor.lfm` `LblTask`/`LblElapsed` absolute-positioned without anchors (drift on resize). |

Clean: `udlgcomicinfoeditor`, `udlgmerge`, `udlgseqbuilder`, `udlgcbr`, `udlgvalidate`, `udlgvalidateopts`, `udlgconvertresults`, `udlgpageview`.

Note: the three alClient siblings in `udlgpageeditor.lfm` (`ImgPreview` / `PaintBoxLines` / `ScrollBoxSlices`) are intentional overlays.

---

## 2. Logical problems

### CRITICAL

- **Save-thread lookup table is corrupted** — `src/upageeditmodel.pas:499-508`. The insertion sort reads its key from `SortedNames[i]` *while shifting into that slot*, so the key is destroyed. (Verified: input `['page_0002.jpg','page_0001.jpg','comicinfo.xml']` sorts to `[0002, 0002, 0002]` — `page_0001` vanishes.) For any CBZ whose entries are not stored in ascending lowercase-name order (the "scrambled archives" the app explicitly supports), `FindIdx` misses pages, causing:
  - pages **silently dropped** from the saved archive (`Continue` at line 539),
  - deleted pages **un-deleted** (unconsumed archive entries re-added by the metadata pass at 574-583),
  - reorders silently undone,
  - wrong bytes written under a `page_NNNN` name (mislabeled content), duplicate names.
  Fix: capture the key in a local before shifting.

### HIGH

- **Preview switch during save = use-after-free** — `TSaveChangesThread` borrows `Data` streams (`upageeditmodel.pas:396`); `ClearPreview` frees them (`main.pas:1052`) while the thread copies them; `SaveChangesThreadTerminated` then compacts the *new* preview's model. Trigger: start Save, double-click another file (or Esc/F5/File→Clear).
- **Batch worker, same class of bug** — `Inputs[].Data` are references (`main.pas:1309`) freed by Revert/Save/Clear during the run; `StageMultiEditResults` (`ubatchedit.pas:269-333`) has no bounds or file guard → AV, or pieces staged into a replaced/closed model (wrong file's pages edited).
- **Gamma stage: `Power(negative, fractional)`** — `src/uimageedit.pas:334-339`. Brightness/contrast run before gamma, the 0..255 clamp runs after → `EInvalidOp` (verified) for any dark pixel when brightness < 0 and gamma ≠ 1. Single editor: "Colour adjustment failed". Batch edit: page **silently skipped**.
- **Keyboard bypasses disabled state** — `KeyPreview = True` + `FormKeyDown`: Ctrl+S starts a *second* save mid-save (`main.pas:575-579`); F8 a second validate; Del mutates the model mid-save; F5 during save triggers the UAF above.
- **PMPages context menu ignores gates** — `SetPageOpsEnabled` (`main.pas:631-647`) disables only the menu items (`MnuPage*`), not the popup items (`MnuPg*`): on a CBR preview the user can Delete/Move via right-click → pending changes with Save and Revert disabled (dead end). `MniMoreBatchEdit` is also never disabled → a second concurrent batch worker.
- **Concurrent services on the same files** — only the triggering control is disabled: Delete-rows + Delete-pages, or Convert + Merge, can interleave `ReplaceCBZ`/`WriteZipFromEntriesDeflated` on the same paths (interleaved rename sequences corrupt or lose data).
- **Esc / F4 / F5 / Close silently discard staged edits** — no confirmation (Revert asks; closing doesn't).

### MEDIUM

- **Add-front images leak** — `MnuPageAddFrontClick` stores the full-res image in `NewPage.Image` without registering it in `FPagePreviews` (`main.pas:2560`); `FreePageImages` nils without freeing → leak per insert, also on Revert.
- **Page editor / page view ignore staged `Data`** — `OpenPageEditor` and `ShowPageView` extract `OrigName` from the archive (`main.pas:1135`): re-editing an already-edited page shows the original and silently discards the earlier edit on OK; inserted split pieces (`OrigName = 'splitN.png'`) cannot be edited or viewed at all.
- **Service terminators reload a cleared folder** — `MnuClearClick` sets `FDir := ''` and stays enabled during services; `ConvertThreadTerminated` etc. call `LoadDirectory(FDir)` → `IncludeTrailingPathDelimiter('')` = `/` → the app scans the **root directory**.
- **`ThreadTerminated` re-enables folder ops while a service runs** — F5 during a convert re-enables `TbConvertWebP`/`TbMerge` when the new directory load completes (`main.pas:2955`).
- **Loader flush handoff race** — `uloaderthread.pas:286-294` vs `404-405`: `FPendingCount := 0` before `SetLength(FPendingBatch, 0)`; the worker's spin gate can hand off a new batch into the truncation window → leaked images + OOB read in the next `SyncAddThumbs`.
- **Queue-based progress on `FreeOnTerminate` threads** — `TSaveChangesThread.DoProgress` and `TMultiEditWorker.DoProgress` use `TThread.Queue`; the sibling `TServiceThread` documents a SIGSEGV with exactly this pattern (queued method running after the self-free).
- **`TDeletePagesThread.Execute` has no try/except** (`uthreadservice.pas:267-306`) — one corrupt CBZ in the batch kills the app.
- **Count-mismatch truncation leaves unbound rows** — `PagesThreadTerminated` binds `It.Data` only for the clamped prefix (`main.pas:2997-3026`); rows beyond keep the SyncAddThumbs rank → double-click edits the wrong page.
- **Multi-select Move Up/Down pinned at the edge swaps inside the block** — `upageeditmodel.pas:179-220`: selection `{0,1}` + Move Up turns `[A,B,C]` into `[B,A,C]` instead of a no-op (same with a `Gone` page adjacent).

### LOW / edge

- Duplicate `OrigName`s in an archive: one page silently dropped on save (binary search claims one entry; `upageeditmodel.pas:523-539`).
- `PageSort` uses locale-aware `AnsiCompareStr` (`upageeditmodel.pas:251-273`) while ranks elsewhere use `CompareStr`.
- Piece names `split1.png` can duplicate when re-splitting a split piece (`ubatchedit.pas:312`).
- Batch dialog header overcounts pieces when duplicate cut lines are added (`udlgbatchedit.pas:309-328` — no dedupe in the dialog).
- Epoch-guard hole for workers created-but-not-started when the epoch bumps (`uloaderthread.pas:250-251`).
- ComicInfo-only removal writes an empty (invalid) ZIP and reports success (`uservicecomicinfo.pas:255-267`).
- `uarchive` calls optional FFI symbols (`archive_entry_pathname_utf8`, `_ArchiveErrorString`, ...) without nil checks — an old libarchive that passes the 4-symbol guard crashes instead of degrading (`uarchive.pas:283-337`).
- `ulog.pas`: observer exceptions escape `Log` (contradicts the never-raises contract); observer runs inside the log lock.

---

## 3. Notable missing features (given the current feature set)

- **Undo/redo** — only whole-session Revert; `FChanges` is a linear log but per-action undo is not exposed.
- **Confirmation/guard rails** when closing a preview with pending edits.
- **Multi-file batch edit** — the batch editor works within one open preview only.
- **Crop / rotate / flip** in the page editor.
- **File-list ergonomics**: sort toggle, search/filter, columns (page count / size / format), drag-and-drop a folder onto the app, recent folders, persisted zoom.
- **Extract/export pages** from a CBZ; create a CBZ from a folder of images.
- **ComicInfo import/export** to/from an external XML file.
- **PDF/EPUB export**, CBZ→CBR conversion.
- **Find-similar/duplicates** and **delete-pages-by-id** — explicitly out of scope per AGENTS.md; still the largest gap vs the Python CLI.
- **Two-page spread / fit modes** in the preview.
- **Dark theme**, shortcut help (H), packaging/installer (only `make install-man` exists).
- **Configurable JPEG quality** (fixed q92) and WebP quality outside convert.
- **Per-file progress** when opening a large preview.

---

## 4. Operation bugs

### Save changes
- Broken lookup sort (CRITICAL above): drops/undeletes/mislabels pages for scrambled archives.
- Renumber/convert use fixed 4-digit padding (`PAGE_PAD_DEFAULT`): `page_10000` sorts before `page_9999`; Python widens padding with count.
- Duplicate `OrigName` → silent page drop (above).

### Convert-webp
- **"Remove ComicInfo.xml" / "Rename to page_NNNN" silently ignored when nothing re-encodes** (`userviceconvert.pas:152-168`): `Modified` is computed by `ConvertCBZToWebP` but never read → "Already up to date" while the checked options take no effect.
- Keeping ComicInfo consumes page slot 1 → first image becomes `page_0002` (`uzipeditor.pas:1272-1284`).
- Backup-then-direct-write (`userviceconvert.pas:154-157`) can leave a corrupt live file on failure; `ReplaceCBZ` exists unused (Python parity, but a real data-safety gap).

### Validate
- Deep validate reports "All images failed to decode" for corrupt archives, masking the real message (`uservicevalidate.pas:203-209`).
- Semantics diverge from the Python reference: a 9-good/1-bad file exits 0 (OK) here vs 1 (FAIL) in Python; an image-less archive FAILs here vs OK there (`uservicevalidate.pas:201`, `uclimode.pas:290-293`).

### Merge
- Chapters in an empty batch are skipped un-cleaned **and** permanently excluded from later batches (`uservicemerge.pas:782-831` — `ChIdx` advances regardless).
- `--chapters` overflow truncates the list and exits 0; Python errors with exit 1 before creating anything.
- Rollback granularity: per-series here vs whole-run in Python — a failure in series B leaves series A's volumes and cleaned chapters in place.
- Volume detection is case-sensitive (`' V'` vs `' v'`); `DetectSeriesName` can latch onto a non-chapter file (`uservicemerge.pas:335, 431-448`).

### CBR→CBZ
- CLI **always exits 0**, even when every file failed (`uclimode.pas:485`).
- Skip-existing is case-sensitive on Linux (`uservicecbr.pas:185-188`): an existing `Manga.CBZ` target is not detected.
- `CollectCbrEntries` leaks collected entries when `ReadData` fails mid-archive (`uzipeditor.pas:1662-1687`).

### ComicInfo
- Removal on a ComicInfo-only archive writes an empty ZIP reported as success.
- Backup-then-direct-write same weakness as convert.

### Leaks on error paths
- `CollectZipEntries` leaks all decompressed entries when extraction raises mid-archive (`uzipcore.pas:98-122`) — the hottest function in the app; a truncated CBZ leaks full-resolution data.
- `ConvertCBZToWebP`: an in-flight worker's late slot write leaks its stream on pool error (`uzipeditor.pas:1236-1255`).
- `uwebp`: buffers leak when `WebPFree` is absent (the documented `FreeMemory` fallback is not implemented).

### CLI
- `--help` after a command prints "unknown option" (exit 2) instead of subcommand help.
- stdout progress from parallel pool workers can interleave.
- `--chapters` parse errors exit 2 vs Python's 1 (Pascal arguably better).

---

## Verified correct (no action needed)

CPV math + documented merge divergences; chapter/volume regex classification; only-if-smaller comparison per page; thread-pool determinism (per-slot results, archive-order compaction); `ReplaceCBZ` four-step rollback; ComicInfo XML parse/generate round-trip; CBR double-scan ranking; delete-source only after successful write; `PageInsertAt`/`PageInsertFront`/`PageDragDrop`/`PageReverse`/`PageRenumber` bounds; `StageMultiEditResults` descending-order arithmetic; `TMultiEditWorker` FreeOnTerminate/OnTerminate result handoff; `ApplyMultiEditToImage` ownership on all paths; `ResampleIntfImage`/`SplitIntfImage`/`ScaleIntfImage` boundary math; `MakeThumb`/`AppendThumb` nil handling; `EncodeExtFor` GIF/TIFF→PNG mapping; magic-byte detection; `TPreviewLoader`/`TSingleImageLoader` lifecycles.

---

## Suggested fix order

1. Save-thread insertion sort (CRITICAL).
2. Use-after-free family: gate preview navigation / editing while the save thread or the batch worker runs (deep-copy Data streams where practical).
3. Gamma clamp before `Power`.
4. Popup-menu gating (`PMPages`, `PMPageMore`) in `SetPageOpsEnabled` + keyboard gating (Ctrl+S/F8/Del).
5. Layout overlaps (stage bar, TabColors pitch in both editors, 300px labels).
6. Then: convert `Modified` handling, validate error message, merge empty-batch bookkeeping, CBR exit code, leak fixes, minor items.
