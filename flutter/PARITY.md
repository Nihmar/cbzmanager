# Flutter port — parity map and checklist

Maps each Lazarus/FPC unit to its actual Flutter target and tracks parity.
Status legend: **Done** · **Partial** · **Deferred** · **N/A**.

_Done_ = implemented at feature level; _Partial_ = core behaviour present with a
documented simplification; _Deferred_ = not ported (see `PLAN.md`).

Paths are relative to `flutter/app/`. Everything under `lib/src/` is the real
tree; the previous version of this file listed paths that never existed
(`engine/convert_webp`, `ui/zoom_controller`, `app/app_logger.dart`,
`features/browser/loader`, `app/app_shell.dart`, …) — do not resurrect them.

---

## 1. Core / engine

| Lazarus unit | Responsibility | Flutter target | Status |
|---|---|---|---|
| `src/uzipcore.pas` | `TZipEntries`, `FormatPageName`, `StripComicInfo`, `FindComicInfoIndex` | `lib/src/engine/zip_ops.dart`, `format.dart` | Done |
| `src/uzipeditor.pas` | ZIP listing/extraction/write, `CollectZipEntries`, WebP conversion, CBR walking | `lib/src/engine/zip_ops.dart`, `dart_engine.dart`, `cbr_convert.dart` | Done |
| `src/uwebp.pas` | WebP decoder/encoder via libwebp (dynamic) | `package:image` (pure Dart); no libwebp FFI yet | Done (pure Dart) |
| `src/uarchive.pas` | CBR reader via libarchive (dynamic) | `lib/src/native/libarchive.dart`, `lib/src/native/cbr_reader.dart` | Done |
| `src/uimgutil.pas` | decode/scale/convert, `EncodeIntfImage`/`EncodeExtFor` | `lib/src/engine/image_edit.dart` (`encodeImage`), `format.dart` (`encodeExtFor`) | Done |
| `src/uimageedit.pas` | `ResampleIntfImage`, `AdjustColors`, `SplitIntfImage` | `lib/src/engine/image_edit.dart` | Done |
| `src/upageeditmodel.pas` | `TPageState`, `TChange`, `PageInsertAt`, save thread | `lib/src/engine/page_model.dart`, `lib/src/features/page_editor/page_edit_service.dart` | Done (save is synchronous per file) |
| `src/ucomicinfo.pas` | parse/generate ComicInfo.xml | `lib/src/engine/comicinfo.dart` | Done |
| `src/ubatchedit.pas` | batch pipeline + worker pool | `lib/src/features/batch_edit/batch_edit_isolate.dart`, `batch_edit_service.dart` | Partial (pool is per-file isolates; no per-page pool) |
| `src/uimgsrc.pas` | image search/download (MangaDex/Openverse/Wikimedia/Open Library/Art Institute/Met/Cleveland/Wellcome/NASA/URL) | `lib/src/engine/image_search.dart` (parsers), `lib/src/features/image_search/image_search_service.dart` (HTTP) | Done (download caps during streaming; requests time out) |
| `src/ulog.pas` | thread-safe logger | none — failures surface in per-file results / snackbars | N/A |

## 2. Services

| Lazarus unit | Responsibility | Flutter target | Status |
|---|---|---|---|
| `src/uservicebase.pas` | shared types, progress, caps, `BackupFile`, `ReplaceCBZ`, file collection | `lib/src/vfs/workspace.dart` (backup/publish), `lib/src/util/cpu.dart`, per-service caps | Partial (`ReplaceCBZ` is `LocalVfs.writeAll` tmp+rename; SMB writes directly) |
| `src/uthreadservice.pas` | background thread wrappers | `lib/src/jobs/job_controller.dart` + isolate wrappers | Done (isolates, not threads) |
| `src/uservicevalidate.pas` | deep validation, per-file pool | `lib/src/features/validate/validate_service.dart`, `validate_isolate.dart` | Done (per file; per-page decode parallel not wired) |
| `src/userviceconvert.pas` | batch WebP conversion | `lib/src/features/convert/convert_service.dart`, `convert_isolate.dart` | Done (quality/only-if-smaller/skip-existing-WebP/ComicInfo/renumber all wired and persisted) |
| `src/uservicemerge.pas` | chapter→volume merge, CPV, batching | `lib/src/engine/merge.dart` (planning), `lib/src/features/merge/merge_service.dart`, `merge_isolate.dart` | Done |
| `src/uservicecbr.pas` | batch CBR→CBZ | `lib/src/features/cbr/cbr_service.dart`, `cbr_isolate.dart` | Done |
| `src/uservicecomicinfo.pas` | scan/remove ComicInfo | `lib/src/features/comicinfo/comicinfo_service.dart`, `comicinfo_isolate.dart` | Done |
| `src/uloaderthread.pas` | directory + single-archive thumbnail pools | `lib/src/features/browser/thumbnail_service.dart`, `thumbnail_isolate.dart` (per-file isolates, bounded pools) | Partial (no sorted batch publication; UI order comes from sorting the listing) |
| `src/upreviewloader.pas` | preview loaders | `lib/src/features/browser/preview_screen.dart` (`ThumbnailService.pageThumbnail`) | Partial |
| `src/uselection.pas` | selection-set helpers | `lib/src/features/browser/selection_controller.dart` | Done (selection is by path, not index) |
| — (GUI-only) | delete pages by range across files | not ported in Flutter; the page editor deletes single pages | Deferred |

## 3. UI / dialogs

| Lazarus unit | Flutter target | Status |
|---|---|---|
| `src/main.pas` / `main.lfm` | `lib/src/main.dart` + `lib/src/features/browser/browser_screen.dart` (single screen, bottom job bar) | Done |
| `src/udlgbase.pas` | inline `AlertDialog`s | N/A |
| `src/udlgrows.pas` | page editor delete/selection | Partial |
| `src/udlgvalidate.pas` / `udlgvalidateopts.pas` | `lib/src/features/validate/validate_results_dialog.dart` (threads live in Settings) | Partial |
| `src/udlgcomicinfo.pas` / `udlgcomicinfoeditor.pas` | `lib/src/features/comicinfo/comicinfo_editor_dialog.dart` | Done (remove is a toolbar action) |
| `src/udlgwebp.pas` | `lib/src/features/convert/convert_dialog.dart` | Done |
| `src/udlgcbr.pas` | `lib/src/features/cbr/cbr_dialog.dart` | Done |
| `src/udlgmerge.pas` | `lib/src/features/merge/merge_dialog.dart` | Done |
| `src/udlgseqbuilder.pas` | `lib/src/features/merge/sequence_builder_dialog.dart` | Partial (chapter list, not a zoomable grid) |
| `src/udlgpageview.pas` | `lib/src/features/browser/preview_screen.dart` | Partial (in-app reader; no floating window) |
| `src/udlgpageeditor.pas` | `lib/src/features/page_editor/page_edit_screen.dart`, `page_editor_dialog.dart` | Partial (delete/move/renumber + resize/colours/split; no zoomable grid) |
| `src/udlgaddimage.pas` | `lib/src/features/image_search/add_image_dialog.dart` | Done |
| `src/udlgbatchedit.pas` | `lib/src/features/batch_edit/batch_edit_dialog.dart` | Done |
| `src/udlgconvertresults.pas` | `lib/src/features/convert/convert_dialog.dart` + results widgets | Done |
| `src/ufrmjobmonitor.pas` | `lib/src/jobs/job_monitor.dart` (bottom bar) | Done |
| `src/usettings.pas` | `lib/src/features/settings/settings.dart`, `settings_dialog.dart` | Done (settings feed the operation dialogs) |
| `src/udlgpageview`/`main` SMB | `lib/src/features/sources/source_controller.dart`, `smb_dialog.dart` | Done (Flutter-only feature) |

## 4. Entrypoints

| Lazarus | Flutter target | Status |
|---|---|---|
| `cbzmanager.lpr` (GUI) | `lib/main.dart` | Done |
| `src/uclimode.pas` (headless CLI) | `bin/cbzmanager.dart` | Partial (validate/convert-webp/merge/cbr-to-cbz; no comicinfo) |
| `man/cbzmanager.1` | `bin/cbzmanager.dart --help` | Partial |

## 5. Behavioural parity checklist

Cross-cutting rules that must be verified before release.

- [x] In-RAM only: no page extraction to disk for any operation.
- [x] Byte-wise sort order for page names (`compareStr`, not locale).
- [x] Non-image entries dropped by merge and convert (never renamed `page_NNNN.ext`); convert keeps ComicInfo unless `removeComicInfo`.
- [x] `format('%s V%.3d.cbz')` volume naming; numbering continues after existing volumes (any digit width).
- [x] CPV auto = `(lowest_chapter - 1) / num_volumes` (real division), default 7.
- [x] "Only if smaller" for WebP conversion; q75; existing `.webp` pages skipped by default (kept byte-identical).
- [x] `_OLD.cbz` backup vs delete semantics (CBR source kept unless delete-source).
- [x] Renumber survivors as `page_NNNN.*`.
- [x] Merge rollback deletes every volume written in the run (partial included) and never a pre-existing file.
- [x] Empty batches produce no volume.
- [x] Deterministic output for any thread count (threads 1 vs N byte-identical).
- [x] Caps: WebP/validate ≤ 8, CBR/merge/batch-edit ≤ 4; `0` = auto.
- [x] CBR previews read-only; missing libarchive degrades gracefully.
- [x] File-level errors never abort a batch (validate/convert/cbr/merge/batch-edit).
- [x] A corrupt archive is rejected as "not a ZIP", not mistaken for an empty one (`isZipData` EOCD guard).
- [x] ComicInfo filtered on the way through convert (flag honoured); merge filters it.
- [x] Editor writes bytes that win over the archive entry; split renumbers all pages.
- [x] GIF/TIFF output maps to PNG; JPEG q92, WebP q75, PNG/BMP lossless.

## 6. Reference documents

- `flutter/README.md`, `flutter/PLAN.md`, `flutter/TARGET.md` — design notes.
- `AGENTS.md` at the repo root — tracked and authoritative; the Python
  reference (`porting/cbz_manager/`) is still untracked and may be absent.
