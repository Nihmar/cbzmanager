# cbzmanager

## Two projects in this repo

| Project | Location | Status |
|---------|----------|--------|
| Lazarus GUI target (active) | `/` (root) | Ported — GUI + headless CLI |
| Flutter port | `flutter/` | Active port (engine + GUI + headless CLI) |
| Python CLI reference | `porting/cbz_manager/` | **Not tracked** (see below) |

The Lazarus GUI is the reference implementation for behaviour, edge cases and
test scenarios. The original Python CLI (`porting/cbz_manager/`) is *outside*
version control (`.gitignore` excludes `porting/`), so a fresh clone has neither
its code nor its `AGENTS.md`: do not treat paths under `porting/` as available
in CI or on a fresh clone.

> **Scope note:** `find-similar` and `delete-pages-by-id` are **out of scope**
> and will not be ported. The batch `delete-pages` operation *is* implemented in
> the Lazarus GUI (`TDeletePagesThread`, `MnuDeletePages`), because it covers
> deleting a page range from several archives at once.

## Commit hygiene

**Make as many commits as possible: one logical change per commit, committed as
soon as it is complete.** Never batch unrelated work into a single commit.

- One commit per bug fix, feature slice, refactor or documentation/asset change.
- The tests for a change belong in the same commit as the change.
- Generated or binary assets (launcher icons, manifests, bindings) ship with the
  change that needs them, not as a separate "update assets" commit.
- Never mix formatting-only churn or unrelated files into a functional commit.
- Commit messages follow the existing history style: `type(scope): summary`,
  imperative mood (`feat`/`fix`/`docs`/`test`/`refactor`/`chore`; scope e.g.
  `flutter`), with a short bullet body explaining the *why* when it is not
  obvious.
- A green `flutter analyze` + `flutter test` (or `make test` on the Lazarus side)
  is the minimum bar before committing.

## Lazarus GUI (root — target for porting)

Lazarus IDE project (`cbzmanager.lpi`). Entrypoint: `cbzmanager.lpr`.
Sources in `src/`.

| File | Role |
|------|------|
| `cbzmanager.lpr` | Program entrypoint |
| `src/main.pas` + `src/main.lfm` | Main form (`TfrmMain`) |
| `src/uzipeditor.pas` | ZIP operations entirely in RAM: listing, image extraction (TUnZipper + FPImage), entry collection (`CollectZipEntries`), ZIP writing (`WriteZipFromEntries`); `ConvertCBZToWebP` parallel decode/encode via a `TWebPConvertWorker` pool (deterministic output regardless of thread count) |
| `src/uzipcore.pas` | Low-level ZIP entry handling: `TZipEntries`, `FormatPageName`, `StripComicInfo`, `FindComicInfoIndex` |
| `src/uwebp.pas` | WebP decoder via libwebp.so (dynamic loading) |
| `src/uarchive.pas` | CBR (RAR) reader via libarchive (dynamic loading, uwebp pattern): `TCbrReader`, `CbrSupported` |
| `src/uloaderthread.pas` | Background thumbnail loading threads (CBZ and CBR); directory load via `OnlineCpuCount` pool (capped at 4); single-archive preview (`TPagesThread`) decodes+scales pages on a worker pool (`AThreads`, default auto capped at 4) or sequential streaming |
| `src/upreviewloader.pas` | Background loaders for preview panes: `TPreviewLoader` (sequence builder), `TSingleImageLoader` (page-view dialog, single full-res entry) |
| `src/uimgutil.pas` | Image decode/scale/convert utilities; `CenterAnchorScrollPos` (shared zoom-anchor math); `EncodeIntfImage`/`EncodeExtFor` (JPEG q92 / PNG / BMP / WebP writers) |
| `src/uimageedit.pas` | Pure page-editor operations (no GUI): `ResampleIntfImage` (box filter, both directions), `AdjustColors` (invert/grayscale/sepia/RGB gains/saturation/contrast/brightness/gamma pipeline), `SplitIntfImage` (N parallel cut lines → N+1 pieces) |
| `src/ulog.pas` | Minimal thread-safe logger |
| `src/uzipeditor.pas` | ZIP operations entirely in RAM: listing, image extraction (TUnZipper + FPImage), entry collection (`CollectZipEntries`), ZIP writing (`WriteZipFromEntries`); `ConvertCBZToWebP` parallel decode/encode via a `TWebPConvertWorker` pool (deterministic output regardless of thread count) |
| `src/upageeditmodel.pas` | In-memory page editing model: `TPageState`, `TChange` (`ckDeleted`/`ckMoved`/`ckEdited`), `PageInsertAt`, `TSaveChangesThread` (edited/inserted pages are saved from their `Data` stream, which wins over the archive entry) |
| `src/uservicebase.pas` | Shared service types, progress callbacks (`TLockedProgress`), `OnlineCpuCount` + `MAX_*_THREADS` caps (8 for WebP/validate, 4 for CBR/merge/batch-edit), `BackupFile`, `ReplaceCBZ`, `CollectCBZFiles`/`CollectCBRFiles` |
| `src/uthreadservice.pas` | Background thread wrappers for validate/convert/merge/comicinfo/cbr services (merge/delete-pages carry a `Threads` pool size, default auto) |
| `src/uservicevalidate.pas` | `TValidateService` — Validate + ValidateDeep (`AThreads` per-file decode pool) |
| `src/userviceconvert.pas` | `TConvertService` — batch WebP conversion |
| `src/uservicemerge.pas` | `TMergeService` — chapter-to-volume merge (volumes planned sequentially, built on a `TMergeVolumeWorker` pool, `AThreads` default auto capped at 4) |
| `src/uservicecbr.pas` | `TConvertCbrService` — batch CBR→CBZ conversion (skip-existing + delete-source options); parallel per-file worker pool (`TCbrConvertWorker`, auto capped at 4) |
| `src/uservicecomicinfo.pas` | `TComicInfoService` — scan/remove ComicInfo.xml (parallel per-file removal pool) |
| `src/ucomicinfo.pas` | ComicInfo.xml parsing and generation (`TComicInfo`, `ParseComicInfoXML`, `GenerateComicInfoXML`) |
| `src/usettings.pas` | Persistent INI-based settings store |
| `src/udlgbase.pas` + `.lfm` | Shared dialog chrome + `TSettingsDialog` base class |
| `src/udlgrows.pas` + `.lfm` | Delete rows by range dialog |
| `src/udlgvalidate.pas` + `.lfm` | Validate results dialog; `src/udlgvalidateopts.pas` — options dialog (parallel decode threads) |
| `src/udlgcomicinfo.pas` + `.lfm` | Remove ComicInfo.xml dialog |
| `src/udlgcomicinfoeditor.pas` + `.lfm` | View/edit ComicInfo.xml dialog |
| `src/udlgwebp.pas` + `.lfm` | Convert to WebP dialog |
| `src/udlgcbr.pas` + `.lfm` | Convert CBR to CBZ dialog (skip-existing + delete-source) |
| `src/udlgmerge.pas` + `.lfm` | Merge chapters dialog (parallel-threads spin, persisted) |
| `src/udlgseqbuilder.pas` + `.lfm` | Custom volume sequence builder (zoomable thumbnails) |
| `src/udlgpageview.pas` + `.lfm` | Non-modal floating page-view window (Space in the main form): full-res page with center-anchored zoom + wheel pan |
| `src/udlgpageeditor.pas` + `.lfm` | Modal page editor (double-click a preview page, Edit button, or context menu): resize (aspect lock), colour adjustments (sliders + live preview + grayscale/sepia/invert), split (draggable cut lines, N lines → N+1 pieces); encodes in the original page format via `EncodeIntfImage` |
| `src/uimgsrc.pas` | Internet image search + download (no GUI, all in RAM): `SearchImages` over Openverse / Wikimedia Commons / pasted URL, `DownloadImage`, `ParseOpenverseResults` / `ParseWikimediaResults` (offline-testable), `GuessExtFromURL`; HTTPS via `fphttpclient` + `opensslsockets` |
| `src/udlgaddimage.pas` + `.lfm` | Modal "add image from internet" dialog (Pages menu, preview context menu, toolbar "Add net"): provider combo + query, results list, thumbnail preview, license line, and "Add" which transfers the downloaded bytes to `AddFrontFromStream` |
| `src/ubatchedit.pas` | Pure batch page-edit pipeline (no GUI): `TMultiEditParams` (percent resize / colour adjust / normalized split lines), `ApplyMultiEditToImage` (decode current state → resize → colours → split → encode pieces), `TMultiEditWorker` background thread pool (per-page workers, `AThreads` default auto capped at 4, sequential fallback; RAM-only, Queue-based progress) |
| `src/udlgbatchedit.pas` + `.lfm` | Modal batch-edit dialog (Pages menu, preview context menu, '...' More popup): uniform percent resize, colour sliders with live preview of the first selected page, and split lines (list + spin, N lines → N+1 pieces per page); header shows "N pages → M pieces"; main.pas stages results into the page model on a background thread |
| `src/udlgconvertresults.pas` + `.lfm` | Conversion results summary dialog |
| `src/ufrmjobmonitor.pas` + `.lfm` | Non-modal job progress monitor window |

### Build (Qt6 widget set)

```bash
fpc -MObjFPC -Scghi -O1 -gw3 -gl -l \
  -Fu/usr/lib/fpc/3.2.2/units/x86_64-linux/rtl \
  -Fu/usr/lib/lazarus/lcl/units/x86_64-linux \
  -Fu/usr/lib/lazarus/lcl/units/x86_64-linux/qt6 \
  -Fu/usr/lib/lazarus/components/lazutils/lib/x86_64-linux \
  -Fu/usr/lib/lazarus/packager/units/x86_64-linux \
  -Fu/usr/lib/lazarus/components/freetype/lib/x86_64-linux \
  -Fu$HOME/.lazarus/lib/units/x86_64-linux/qt6 \
  -Fusrc -Fulib \
  -FEbin/debug/x86_64-linux -FUobj/debug/x86_64-linux \
  -dLCL -dLCLqt6 \
  cbzmanager.lpr
```

### Make targets

```bash
make build          # debug build with fpc (Qt6 widget set)
make release        # release build (O3, smart link, strip)
make test           # compile and run FPCUnit test suite (QT_QPA_PLATFORM=offscreen)
make test-compile   # compile test runner only
make test-checks    # compile test runner with -Cr -Co -Ci -Ct -gh (heaptrc) and run offscreen
make man            # lint man page (requires groff)
make install        # install binary, man page, icon, and .desktop entry to /usr
make install-man    # install man page only to $(DESTDIR)$(PREFIX)/share/man/man1
make pkg            # build and install an Arch Linux package
make clean          # remove test build artifacts
```

### Operations to port (from Python reference)

| Operation | Python module | Behaviour | Status |
|-----------|---------------|-----------|--------|
| **validate** | `validate.py` | Check CBZ is a valid ZIP and all images (incl. `.webp`) are readable; per-file decode pool (`--threads N`, GUI options dialog, default one worker per CPU core capped at 8) | ✅ Ported |
| **convert-webp** | `convert.py` | Convert images to WebP (quality 75%) only if smaller; filter `ComicInfo.xml`; rename to `page_NNNN.*`; backup originals as `_OLD.cbz` or `--delete`; parallel decode+encode via a worker pool (`--threads N`, GUI spin-edit, default one worker per CPU core capped at 8) | ✅ Ported |
| **merge** | `merge.py` | Merge chapter CBZ (`Title - NNNN.cbz`) into volumes (`Title VNNN.cbz`); auto-calculate CPV `(lowest_chapter-1)/num_volumes` (float, Python-exact) or default **7**; supports `--force`, `--chapters`, `--chapters-per-volume`; volumes built in parallel via a worker pool (`--threads N`, GUI spin-edit, default one worker per CPU core capped at 4) | ✅ Ported |
| **remove-comicinfo** | — | Scan or strip `ComicInfo.xml` from CBZ archives; optional backup | ✅ Ported (GUI) |
| **cbr-to-cbz** | — | Convert CBR (RAR) archives to CBZ entirely in RAM via libarchive (dynamic loading, uwebp pattern); read-only .cbr previews; skip existing targets, optional delete source; files converted in parallel via a worker pool (`--threads N`, GUI spin-edit, default one worker per CPU core capped at 4) | ✅ GUI + CLI (no Python counterpart) |
| **delete-pages** | `delete_pages.py` | Delete pages by 1-indexed position (entries sorted alphabetically); renumber survivors as `page_NNNN.*` | ✅ Ported (GUI, parallel per file) |
| **find-similar** | `find_similar.py` | 64-bit difference hash via PIL; group by Hamming distance (threshold default 10); extract groups | ❌ Out of scope |
| **delete-pages-by-id** | `delete_by_id.py` | Delete entries by `filename.cbz:entry_name.ext` ID (CSV or file); renumber survivors | ❌ Out of scope |

### Common behaviours (all operations)

- **All ZIP operations happen entirely in RAM.** Use `TUnZipper` with `OnCreateStream`/`OnDoneStream` to capture entries into `TMemoryStream`. Use `CollectZipEntries` to read a CBZ into memory and `WriteZipFromEntries` to write a new CBZ. The only disk writes are the final output file and the optional `_OLD.cbz` backup. Never write temp files or extract to disk. **CBR operations obey the same rule** via libarchive (uarchive.pas): the .cbr source is opened read-only, entries decompress into `TMemoryStream` (`CollectCbrEntries`/`ForEachCbrImage`).
- Filter out `ComicInfo.xml` zip entries
- Rename all remaining images sequentially as `page_NNNN.*`
- Backup originals as `_OLD.cbz` unless `--delete` (or equivalent GUI option) — for CBR the source is kept unless the explicit delete-source option is set
- RAR archives have no central directory: the CBR walkers scan the archive twice (names first for alphabetical ranks, then data)
- **Convert-webp decodes/encodes pages in parallel** (`ConvertCBZToWebP`): a pool of `TWebPConvertWorker` threads claims convertible entries under a lock and writes each result into a per-entry slot, then a sequential pass compacts and renumbers in archive order — so the output is byte-identical for any thread count (0 = CPU cores, capped at 8; each worker holds one full-resolution image in RAM). `DecodeImage`/`IntfImageToWebP` are stateless per call, so workers share nothing but the pool state.
- **Cbr-to-cbz converts files in parallel** (`TConvertCbrService.Convert`): RAR decompression inside libarchive is single-threaded, so the parallel unit is the whole file (read → filter → write → optional source delete). A pool of `TCbrConvertWorker` threads claims file indices under a lock and writes per-file results into their own slots (deterministic order); within-file progress is serialized through `TLockedProgress`. 0 = CPU cores, capped at 4 (every worker holds a whole decompressed archive in RAM). Errors are per-file, never fatal to the batch.
- **Validate decodes pages in parallel** (`ValidateCBZImages`): the per-image checks land in per-source-index slots and are assembled in archive order after the join, so results are identical for any thread count. 0 = CPU cores, capped at 8 (same `TValidateWorker` pool shape as the WebP conversion). File-level errors (unreadable archive, empty ZIP) still surface as a single invalid pseudo-entry.
- **ComicInfo removal runs per file in parallel** (`TComicInfoService.Remove`): `TCbrConvertWorker`-style pool (claim index → `RemoveOne` → own result slot, cap 4); `TLockedProgress` (now in uservicebase) serializes within-file progress for both pools.
- **Merge builds volumes in parallel** (`TMergeService.Merge`): batches are planned sequentially (Python-exact CPV/force/custom-seq logic, preassigned `VNNN` names), then a pool of `TMergeVolumeWorker` threads claims batch indices and writes each volume file (own `TUnZipper`/`TZipper` instances per call); per-batch Wrote flags drive rollback (partial writes included) and source cleanup after the join — byte-identical per volume for any thread count. 0 = CPU cores, capped at 4 (each worker holds a whole volume in RAM).
- **Batch page-edit runs per page in parallel** (`TMultiEditWorker`): workers claim input indices and run the decode → resize → colours → split → encode pipeline into per-index slots; failures abort the batch like the sequential path. 0 = CPU cores, capped at 4, sequential fallback.
- **Single-archive previews decode pages in parallel** (`TPagesThread`, `TPreviewLoader`): the archive is collected once, then workers decode + scale pages (JPEG DCT fast path preserved) into rank slots; the main-thread batch publication is unchanged. Sequential streaming remains for `Threads=1`.
- **Batch delete-pages runs per file in parallel** (`TDeletePagesThread`): pool with per-file result slots aggregated in order after the join; per-file failures never abort the batch. 0 = CPU cores, capped at 4, sequential fallback.

### Merge — documented divergences from the Python reference

The merge port is Python-exact for classification, CPV arithmetic (real
division), volume numbering, batching, page ordering (`sorted(namelist())`),
and rollback. The following divergences are **intentional**:

- **Non-image entries are dropped**, not renumbered as pages (a `credits.txt`
  in a chapter never becomes `page_001.txt`). Same house policy as
  convert/filter. Consequence: padding is computed from the image count.
- **Force below CPV creates a single volume** (e.g. 5 chapters, CPV 7, force →
  1 volume of 5). Python skips entirely even with `--force`.
- **CPV < 1 with volumes present falls back to 7** (e.g. volumes exist and
  the lowest remaining chapter is 1). Python crashes (`ZeroDivisionError`)
  or writes empty volumes.
- **Chapter range** (`ChapterStart`/`ChapterEnd`): a GUI feature; the default
  covers every chapter (start 0), so chapter `0` files (`Series - 0000.cbz`)
  merge like the Python reference does.
- **`.CBZ` glob is case-insensitive** (Python's `*.cbz` glob is case-sensitive).
- **Empty batches produce no volume file** (Python writes an empty CBZ).
- **`GenerateComicInfo.xml` per volume** is a GUI-only option (Python has none).
- Multi-series folders are merged per series (one dialog run per series).

### CBR — divergences and notes

- **CBR support has no Python counterpart.** RAR archives are read via
  libarchive (loaded dynamically like libwebp); when libarchive is missing
  the GUI degrades (no .cbr thumbnails; opening one reports the missing
  dependency) and `cbr-to-cbz` exits 1.
- **CBR previews are read-only** in the main window (RAR cannot be rewritten
  in place): page operations and the stage bar are disabled; the CBR→CBZ
  conversion is the path to editing. `GetFileList` filters by extension, so
  batch operations (validate/convert/merge/comicinfo) never receive `.cbr`.
- **Windows**: the library search tries `archive.dll` (vcpkg) then
  `libarchive.dll`; paths are opened with the wide-character
  `archive_read_open_filename_w` and entry names via
  `archive_entry_pathname_utf8` (LCL strings are UTF-8 on both platforms).

### Page editor — notes

The modal page editor (`udlgpageeditor`) is opened from the preview pane
(double-click a page, the Edit button, or the context menu) and stages its
result into the in-memory model — nothing is written until "Save changes".

- **Replace mode (resize / colour adjust)** keeps the page's slot, `OrigName`
  and name (extension updated when the encoded format changes, e.g.
  GIF/TIFF → PNG).  The encoded bytes go into `TPageState.Data`, which the
  save thread now prefers over the archive entry.
- **Split mode** replaces the page with the first piece and inserts the
  remaining pieces after it (`PageInsertAt`); `FRenumber` + `PageRenumber`
  then rename every visible page `page_NNNN.*`, so all following pages get
  the next sequential names.  Cut lines are added with the "Add line" button
  or by dragging on the preview (a drag with no line nearby creates one);
  OK derives the result from state — any cut line means split, so a skipped
  or failed "Apply split" can never silently fall back to replace mode, and
  OK refuses to close when nothing was changed.
- **Output format** is the page's original (JPEG re-encoded at q92, WebP at
  q75, PNG/BMP lossless); GIF/TIFF have no FPC writer and map to PNG
  (`uimgutil.EncodeExtFor`).  Decoding is magic-byte based app-wide, so the
  renamed extension is purely cosmetic.
- **CBR previews are read-only**: the editor entry points are gated by
  `IsReadOnlyPreview`, like every other page operation.
- **Add image from internet** (`udlgaddimage` + `uimgsrc`): inserts a
  web-sourced image as the new first page. The dialog searches Openverse or
  Wikimedia Commons (free, key-less search APIs) or accepts a pasted image
  URL, downloads the chosen bytes, and stages them via the shared
  `AddFrontFromStream` helper (same path as the local "Add front" file
  action) — `IsReadOnlyPreview`-gated and committed only through the stage
  bar.  Network is `fphttpclient` + `opensslsockets`; Openverse is
  rate-limited for anonymous use (surfaced as a clear error).
- The zoom debounce timer rebuilds the page thumbnails from `FPages`
  (visible pages) instead of the `FPagePreviews` cache, which is no longer
  index-aligned with the page list after edits/splits (also fixes the
  pre-existing insert-front misalignment).
- Edited/split thumbnails are appended to `FPagePreviews` (the cache owns
  them); Revert/Close simply drop them, so no ownership surgery is needed.

### Headless (CLI) mode

The same binary acts as a CLI when the first argument is a known command
(`validate`, `convert-webp`, `merge`, `cbr-to-cbz`, `--help`, `--version`) —
the headless branch in `cbzmanager.lpr` runs before any widgetset
initialization, so no display is needed (proven by the FPCUnit runner,
which also never initializes the widgetset). Implementation:
`src/uclimode.pas` (`RunHeadless`/`IsHeadlessCommand`); tests:
`tests/test_uclimode.pas`.

```bash
cbzmanager validate <dir> [--threads N]   # ValidateDeep over *.cbz
cbzmanager convert-webp <dir> [--delete] [--threads N]  # Python defaults: q75, only-if-smaller, strip ComicInfo, renumber
cbzmanager merge <dir> [--delete] [--force] [--chapters N1,N2] [--chapters-per-volume N] [--threads N]
cbzmanager cbr-to-cbz <dir> [--delete] [--threads N]  # convert CBR archives; skip existing targets, keep source by default
```

- Flags may precede or follow the directory (argparse tolerance).
- Exit codes: 0 success/benign no-op, 1 runtime error, 2 usage error
  (mirrors the Python CLI; mutual exclusion of `--chapters` and
  `--chapters-per-volume` returns 1 like the reference).
- `merge` runs one `TMergeService.Merge` per series found (sorted, like
  the Python `all_series` loop) with `ChapterStart=0`, `ChapterEnd=MaxInt`,
  no ComicInfo generation, `AThreads` from `--threads` (0 = auto, cap 4).
- `cbr-to-cbz` exits 1 with an explanatory message when libarchive is
  unavailable at runtime.
- Differential verification against the CLI: regenerate the fixture
  script (see git history for `diffcli.py`) or re-run the FPCUnit suite.

## Tests

27 `test_*.pas` files in `tests/` (26 test units + the shared `test_helpers.pas`) plus `testrunner.pp`. Run with `make test`.
| Test file | Coverage |
|-----------|----------|
| `tests/testrunner.pp` | Test runner |
| `tests/test_helpers.pas` | Shared test utilities (`CreateMinimalPNGStream`, `CreateNoisePNGStream`, `ZipFilesEqual` — archive comparison by entry content, immune to ZIP write timestamps) |
| `tests/test_uzipeditor.pas` | ZIP read/write, image counting, entry filtering, CBR walking/decoding/conversion (zip-format `.cbr` fixtures; real-RAR test guarded on `rar` availability), parallel-WebP determinism (threads 1 vs 4 → byte-identical) |
| `tests/test_uservicevalidate.pas` | Validate + ValidateDeep services (threads=1 vs 4 → identical per-image checks) |
| `tests/test_uclimode.pas` | Headless CLI argument parsing and dispatch (incl. `--threads`) |
| `tests/test_uservicemerge.pas` | Merge service classification, CPV calc, batching, force mode, parallel-volume determinism (threads 1 vs 4 → byte-identical) |
| `tests/test_uservicecomicinfo.pas` | ComicInfo scan/remove service (threads=1 vs 4 → identical archives, backup under pool) |
| `tests/test_ucomicinfo.pas` | ComicInfo XML parse/generate round-trip |
| `tests/test_udlgseqbuilder.pas` | Sequence builder preview and sequence logic |
| `tests/test_udlgpageview.pas` | Floating page-view dialog page loading |
| `tests/test_upageeditmodel.pas` | Page edit model (delete, reorder, renumber, insert-at, save Data precedence) |
| `tests/test_uimageedit.pas` | Page-editor ops: colour pipeline, resample, split, encode round-trips |
| `tests/test_ubatchedit.pas` | Batch page-edit pipeline: param neutrality, percent resize, colours, split pieces, ext mapping, worker decode + Data-precedence, pool progress monotonicity (explicit Threads=4) |
| `tests/test_uselection.pas` | Selection-set helpers: RangeSel/ToggleSel/UnionSel/HasSel (order, dedupe, reversal) |
| `tests/test_udlgbatchedit.pas` | Batch-edit dialog .lfm streaming + ExtractParams round-trip |
| `tests/test_uimgsrc.pas` | Offline tests for `uimgsrc`: Openverse/Wikimedia JSON parsing, URL provider, ext guessing |
| `tests/test_uthreadservice.pas` | Service-thread progress plumbing (Synchronize-based dispatch; regression for the WebP-conversion crash) + delete-pages pool determinism (threads 1 vs 4 → identical archives) |
| `tests/test_mainform.pas` | Main-form streaming smoke test: every handler named in `main.lfm` exists after `TfrmMain.Create` (regression for the `OnSelectItem` crash) |
| `tests/test_uloaderthread.pas` | Thumbnail loader/coordinator behaviour (cancellation, batch ownership) |
| `tests/test_udlgcbr.pas`, `tests/test_udlgvalidate.pas`, `tests/test_udlgvalidateopts.pas`, `tests/test_udlgcomicinfoeditor.pas`, `tests/test_udlgmerge.pas`, `tests/test_udlgpageeditor.pas`, `tests/test_udlgwebp.pas` | Dialog `.lfm` streaming / options round-trips |
| `tests/test_userviceconvert.pas` | Batch WebP conversion service (threads=1 vs 4 → identical archives by content) |
| `tests/test_uservicecbr.pas` | Batch CBR→CBZ service (threads=1 vs 4 → identical archives by content, skip-existing, delete-source) |

Test data is generated dynamically in `test_helpers.pas`. No fixtures in the
repository.

## Architecture highlights (main.pas)

- **Two-pane UI**: left `LVFiles` (file browser with first-page thumbnails), right `LVPages` (page preview/editor).
- **Threading**: all heavy I/O on background threads (`TLoadThread`, `TPagesThread`, `TSaveChangesThread`, service threads). Progress reported via `TThread.Queue`.
- **Page editing model** (`upageeditmodel.pas`): `FPages` (working state), `FBaseline` (open-time snapshot for revert), `FChanges` (linear log for undo). Stage bar appears when changes are pending.
- **Thumbnail cache**: `TLazIntfImageList` instances at 320×400 resolution. Zoom slider rebuilds icons on-the-fly via `RebuildThumbs` with debounce.
- **Job Monitor** (`ufrmjobmonitor.pas`): non-modal floating window with progress bar, task label, elapsed time, and scrolling log.
- **Page View** (`udlgpageview.pas`): non-modal floating window opened with Space in the main form; shows the selected page extracted full-res from disk via `GetImageAsIntfImage`, with the same wheel zoom/pan as the sequence builder preview (center-anchored Ctrl+wheel zoom, wheel pan top-to-bottom, shift+wheel pan left/right).
- **Settings persistence** (`usettings.pas`): INI file in `GetAppConfigDir`, survives between dialog runs.

## Python CLI reference (`porting/cbz_manager/` — not tracked)

The reference implementation is excluded from version control; the paths below
only exist in a working copy that still has it. The quick-start commands are
kept for that case.

Use the Python project to verify behaviour when porting.

### Quick start

```bash
cd porting/cbz_manager
uv sync
uv run cbz-manager validate <dir>
uv run cbz-manager convert-webp <dir> [--delete]
uv run cbz-manager merge <dir> [--delete] [--force] [--chapters N,N] [--chapters-per-volume N]
uv run cbz-manager <dir> delete-pages --pages "3,5-20"
uv run cbz-manager <dir> find-similar --output ./out [--threshold 10]
uv run cbz-manager <dir> delete-pages-by-id --ids "f.cbz:p.png" [--delete]
```

### Development (Python)

```bash
uv run pytest                  # all tests
uv run pytest tests/test_X.py  # single test file
uv run ruff check src tests    # lint (line-length 100, target py310)
```

Full detail in `porting/cbz_manager/AGENTS.md`.

