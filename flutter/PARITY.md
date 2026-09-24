# Flutter port — Parity map and checklist

Maps each Lazarus/FPC unit to its Flutter target and tracks parity.
Status legend: **Done** · **Partial** · **Deferred** · **N/A**.

_Done_ = implemented at feature level; _Partial_ = core behaviour present with a
documented simplification; _Deferred_ = not ported (see `PLAN.md`).

---

## 1. Core / engine

| Lazarus unit | Responsibility | Flutter target | Status |
|---|---|---|---|
| `src/uzipcore.pas` | `TZipEntries`, `FormatPageName`, `StripComicInfo`, `FindComicInfoIndex` | `engine/` ZIP entry model + naming | Done |
| `src/uzipeditor.pas` | ZIP listing/extraction/write, `CollectZipEntries`, `WriteZipFromEntries`, `ConvertCBZToWebP`, CBR walking | `engine/zip_ops`, `engine/convert_webp` | Done |
| `src/uwebp.pas` | WebP decoder via libwebp (dynamic) | `image` package (pure Dart); optional libwebp FFI | Done |
| `src/uarchive.pas` | CBR reader via libarchive (dynamic) | `engine/cbr_reader` + libarchive dynamic load | Done |
| `src/uimgutil.pas` | decode/scale/convert, `CenterAnchorScrollPos`, `EncodeIntfImage`/`EncodeExtFor` | `engine/image_util`, `ui/zoom_controller` | Done |
| `src/uimageedit.pas` | `ResampleIntfImage`, `AdjustColors`, `SplitIntfImage` | `engine/image_edit` | Done |
| `src/upageeditmodel.pas` | `TPageState`, `TChange`, `PageInsertAt`, `TSaveChangesThread` | `features/page_editor/model` | Done |
| `src/ucomicinfo.pas` | parse/generate ComicInfo.xml | `engine/comicinfo` | Done |
| `src/ubatchedit.pas` | batch pipeline + worker pool | `features/batch_edit/engine` | Done |
| `src/uimgsrc.pas` | image search/download (MangaDex/Openverse/Wikimedia/Open Library/Art Institute/Met/Cleveland/Wellcome/NASA/URL) | `features/image_search/client` | Done |
| `src/ulog.pas` | thread-safe logger | `app/app_logger.dart` | Done |

## 2. Services

| Lazarus unit | Responsibility | Flutter target | Status |
|---|---|---|---|
| `src/uservicebase.pas` | shared types, `TLockedProgress`, `OnlineCpuCount`, caps, `BackupFile`, `ReplaceCBZ`, file collection | `jobs/`, `vfs/workspace`, `engine/threads` | Done |
| `src/uthreadservice.pas` | background thread wrappers (merge/delete-pages/...) | `jobs/job_controller` | Done |
| `src/uservicevalidate.pas` | `TValidateService`, deep validation, per-file pool | `features/validate/engine` | Done |
| `src/userviceconvert.pas` | batch WebP conversion | `features/convert_webp/engine` | Done |
| `src/uservicemerge.pas` | chapter→volume merge, CPV, batching | `features/merge/engine` | Done |
| `src/uservicecbr.pas` | batch CBR→CBZ | `features/cbr/engine` | Done |
| `src/uservicecomicinfo.pas` | scan/remove ComicInfo | `features/comicinfo/engine` | Done |
| `src/uloaderthread.pas` | directory + single-archive thumbnail pools | `features/browser/loader` | Done |
| `src/upreviewloader.pas` | preview loaders (sequence + single image) | `features/browser/preview_loader` | Done |
| `src/uselection.pas` | selection-set helpers | `ui/selection.dart` | Done |

## 3. UI / dialogs

| Lazarus unit | Flutter target | Status |
|---|---|---|
| `src/main.pas` / `main.lfm` | `app/app_shell.dart` (two-pane + adaptive) | Done |
| `src/udlgbase.pas` | `ui/components/app_dialog.dart` | Done |
| `src/udlgrows.pas` | `features/page_editor/delete_rows_dialog.dart` | Partial (delete is in the page editor) |
| `src/udlgvalidate.pas` / `udlgvalidateopts.pas` | `features/validate/` screens | Done |
| `src/udlgcomicinfo.pas` / `udlgcomicinfoeditor.pas` | `features/comicinfo/` screens | Done |
| `src/udlgwebp.pas` | `features/convert_webp/dialog.dart` | Done |
| `src/udlgcbr.pas` | `features/cbr/dialog.dart` | Done |
| `src/udlgmerge.pas` | `features/merge/dialog.dart` | Done |
| `src/udlgseqbuilder.pas` | `features/merge/sequence_builder.dart` | Partial (chapter list, not a zoomable grid) |
| `src/udlgpageview.pas` | `features/browser/page_view.dart` | Partial (preview has zoom; no floating window) |
| `src/udlgpageeditor.pas` | `features/page_editor/editor.dart` | Partial (equal-size split; drag-and-drop reorder done, no draggable lines) |
| `src/udlgaddimage.pas` | `features/image_search/dialog.dart` | Done |
| `src/udlgbatchedit.pas` | `features/batch_edit/dialog.dart` | Done |
| `src/udlgconvertresults.pas` | `features/*/results_dialog.dart` | Done |
| `src/ufrmjobmonitor.pas` | `jobs/job_monitor.dart` (window/bottom sheet) | Done |
| `src/usettings.pas` | `features/settings/store.dart` | Done |

## 4. Entrypoints

| Lazarus | Flutter target | Status |
|---|---|---|
| `cbzmanager.lpr` (GUI) | `app/lib/main.dart` | Done |
| `src/uclimode.pas` (headless CLI) | `bin/cbzmanager.dart` | Partial (validate/convert-webp/merge/cbr-to-cbz; no comicinfo) |
| `man/cbzmanager.1` | `bin/cbzmanager.dart --help` | Partial |

## 5. Behavioural parity checklist

Cross-cutting rules that must be verified before release.

- [ ] In-RAM only: no page extraction to disk for any operation.
- [ ] Byte-wise sort order for page names (`compareStr`, not locale).
- [ ] Non-image entries dropped by convert/merge (house policy).
- [ ] `format('%s V%.3d.cbz')` volume naming; numbering continues after existing volumes.
- [ ] CPV auto = `(lowest_chapter - 1) / num_volumes` (real division), default 7.
- [ ] "Only if smaller" for WebP conversion; q75.
- [ ] `_OLD.cbz` backup vs delete semantics (CBR source kept unless delete-source).
- [ ] Renumber survivors as `page_NNNN.*`.
- [ ] Merge rollback deletes every volume written in the run (partial included).
- [ ] Empty batches produce no volume.
- [ ] Deterministic output for any thread count (threads 1 vs N byte-identical).
- [ ] Caps: WebP/validate ≤ 8, CBR/merge/batch-edit ≤ 4; `0` = auto.
- [ ] CBR previews read-only; missing libarchive degrades gracefully.
- [ ] File-level errors never abort a batch (validate/convert/cbr/delete-pages).
- [ ] ComicInfo filtered on the way through convert/merge.
- [ ] Editor writes bytes that win over the archive entry; split renumbers all pages.
- [ ] GIF/TIFF output maps to PNG; JPEG q92, WebP q75, PNG/BMP lossless.
- [ ] Sorting/selection semantics: plain click replaces, Ctrl toggles, Shift extends, empty click clears.

## 6. Reference documents

- `AGENTS.md` — behaviour, divergences, architecture of the reference.
- `porting/cbz_manager/` — Python reference implementation (local).
