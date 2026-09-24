# Flutter port — Parity map and checklist

Maps each Lazarus/FPC unit to its Flutter target and tracks parity.
Status legend: **Todo** · **WIP** · **Done** · **N/A**.

---

## 1. Core / engine

| Lazarus unit | Responsibility | Flutter target | Status |
|---|---|---|---|
| `src/uzipcore.pas` | `TZipEntries`, `FormatPageName`, `StripComicInfo`, `FindComicInfoIndex` | `engine/` ZIP entry model + naming | Todo |
| `src/uzipeditor.pas` | ZIP listing/extraction/write, `CollectZipEntries`, `WriteZipFromEntries`, `ConvertCBZToWebP`, CBR walking | `engine/zip_ops`, `engine/convert_webp` | Todo |
| `src/uwebp.pas` | WebP decoder via libwebp (dynamic) | `image`/Rust `webp` (Option B) or libwebp FFI (A) | Todo |
| `src/uarchive.pas` | CBR reader via libarchive (dynamic) | `engine/cbr_reader` + libarchive dynamic load | Todo |
| `src/uimgutil.pas` | decode/scale/convert, `CenterAnchorScrollPos`, `EncodeIntfImage`/`EncodeExtFor` | `engine/image_util`, `ui/zoom_controller` | Todo |
| `src/uimageedit.pas` | `ResampleIntfImage`, `AdjustColors`, `SplitIntfImage` | `engine/image_edit` | Todo |
| `src/upageeditmodel.pas` | `TPageState`, `TChange`, `PageInsertAt`, `TSaveChangesThread` | `features/page_editor/model` | Todo |
| `src/ucomicinfo.pas` | parse/generate ComicInfo.xml | `engine/comicinfo` | Todo |
| `src/ubatchedit.pas` | batch pipeline + worker pool | `features/batch_edit/engine` | Todo |
| `src/uimgsrc.pas` | image search/download (MangaDex/Openverse/Wikimedia/URL) | `features/image_search/client` | Todo |
| `src/ulog.pas` | thread-safe logger | `app/app_logger.dart` | Todo |

## 2. Services

| Lazarus unit | Responsibility | Flutter target | Status |
|---|---|---|---|
| `src/uservicebase.pas` | shared types, `TLockedProgress`, `OnlineCpuCount`, caps, `BackupFile`, `ReplaceCBZ`, file collection | `jobs/`, `vfs/workspace`, `engine/threads` | Todo |
| `src/uthreadservice.pas` | background thread wrappers (merge/delete-pages/...) | `jobs/job_controller` | Todo |
| `src/uservicevalidate.pas` | `TValidateService`, deep validation, per-file pool | `features/validate/engine` | Todo |
| `src/userviceconvert.pas` | batch WebP conversion | `features/convert_webp/engine` | Todo |
| `src/uservicemerge.pas` | chapter→volume merge, CPV, batching | `features/merge/engine` | Todo |
| `src/uservicecbr.pas` | batch CBR→CBZ | `features/cbr/engine` | Todo |
| `src/uservicecomicinfo.pas` | scan/remove ComicInfo | `features/comicinfo/engine` | Todo |
| `src/uloaderthread.pas` | directory + single-archive thumbnail pools | `features/browser/loader` | Todo |
| `src/upreviewloader.pas` | preview loaders (sequence + single image) | `features/browser/preview_loader` | Todo |
| `src/uselection.pas` | selection-set helpers | `ui/selection.dart` | Todo |

## 3. UI / dialogs

| Lazarus unit | Flutter target | Status |
|---|---|---|
| `src/main.pas` / `main.lfm` | `app/app_shell.dart` (two-pane + adaptive) | Todo |
| `src/udlgbase.pas` | `ui/components/app_dialog.dart` | Todo |
| `src/udlgrows.pas` | `features/page_editor/delete_rows_dialog.dart` | Todo |
| `src/udlgvalidate.pas` / `udlgvalidateopts.pas` | `features/validate/` screens | Todo |
| `src/udlgcomicinfo.pas` / `udlgcomicinfoeditor.pas` | `features/comicinfo/` screens | Todo |
| `src/udlgwebp.pas` | `features/convert_webp/dialog.dart` | Todo |
| `src/udlgcbr.pas` | `features/cbr/dialog.dart` | Todo |
| `src/udlgmerge.pas` | `features/merge/dialog.dart` | Todo |
| `src/udlgseqbuilder.pas` | `features/merge/sequence_builder.dart` | Todo |
| `src/udlgpageview.pas` | `features/browser/page_view.dart` | Todo |
| `src/udlgpageeditor.pas` | `features/page_editor/editor.dart` | Todo |
| `src/udlgaddimage.pas` | `features/image_search/dialog.dart` | Todo |
| `src/udlgbatchedit.pas` | `features/batch_edit/dialog.dart` | Todo |
| `src/udlgconvertresults.pas` | `features/*/results_dialog.dart` | Todo |
| `src/ufrmjobmonitor.pas` | `jobs/job_monitor.dart` (window/bottom sheet) | Todo |
| `src/usettings.pas` | `features/settings/store.dart` | Todo |

## 4. Entrypoints

| Lazarus | Flutter target | Status |
|---|---|---|
| `cbzmanager.lpr` (GUI) | `app/lib/main.dart` | Todo |
| `src/uclimode.pas` (headless CLI) | optional `flutter/cli/` (see PLAN §10 Q3) | Todo |
| `man/cbzmanager.1` | `flutter/docs/cli.md` (if CLI shipped) | Todo |

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
- `origin/porting/tauri` — Rust core and its `PLAN.md` / `TARGET.md` / `GAPS.md`.
