# cbzmanager — Tauri (Rust/Svelte) vs Lazarus (FPC/LCL): Feature Comparison & Bug Hunt

**Repository:** `/home/alessandro/Projects/cbzmanager`
- **Lazarus (shipped / active target):** root project `cbzmanager.lpi`, entry `cbzmanager.lpr`. GUI + headless CLI in one binary. LCL/FreePascal.
- **Tauri port:** `porting/tauri/` — Rust workspace (`rust-core` lib, `cbzmanager-cli`, `cbzmanager-tauri`) + Svelte 4 TS frontend (`web/`). Tauri v2 shell.
- **Python reference:** `porting/cbz_manager/` — CLI spec only (out of scope for GUI; validate/convert/merge are the behavioural golden model).

> Iterative working document. Findings below are verified from source with `file:line` refs where stated. Empty/scaffolded vs complete is called out explicitly.

---

## 1. Executive summary

- Both projects implement the same core engine (validate, convert-webp, merge, comicinfo, cbr→cbz, in-place page editor, batch edit, CLI). The **Lazarus version is the completed, shipped product**; the **Tauri port has a complete + battle-tested Rust *core* and CLI**, but its **Tauri/Svelte GUI was actively implemented at capture time** — all 5 operations are wired end-to-end (17 registered IPC commands), which contradicts the `PLAN.md` checkpoint-6 marker that says "🔴 Empty scaffold". The docs lag the code.
- **Rust core CLI ≈ Lazarus CLI in feature parity.** Divergences are largely intentional and documented.
- **Shared design invariant in both:** every ZIP/CBR operation is performed entirely in RAM (no temp files on disk); only final output + optional `_OLD.cbz` backup touch disk. CBR reads RAR via dynamic-loading of libarchive, gracefully degrading when absent.
- **Bug hunt turned up real issues in BOTH**, plus several shared/parity bugs and a handful of cosmetic divergences. Highest-value findings are flagged ⚠️ in the bug sections.

---

## 2. Architecture comparison

| Aspect | Lazarus (`src/`) | Tauri port (`porting/tauri/`) |
|---|---|---|
| Language / toolkit | FreePascal + LCL (Qt6 widgetset) | Rust + Tauri v2 + Svelte 4/TS webview |
| Entry | `cbzmanager.lpr` (GUI vs CLI dispatch before widgetset init via `uclimode.pas`) | `src-tauri/src/main.rs`; commands in `src-tauri/src/commands/*.rs` |
| Core logic | GUI-free service units (`uservice*.pas`) + pure edit units (`uzipeditor`, `ucomicinfo`, `ubatchedit`) | `rust-core/src/*.rs` (GUI-free lib) |
| ZIP engine | `uzipcore.pas`/`uzipeditor.pas`: TUnZipper streams fully in RAM; `CollectZipEntries`/`WriteZipFromEntriesDeflated` | `zip_ops.rs`: `zip` crate, same collect/write + RAM-only rule |
| Image decode | `uimgutil.pas` + FPImage; magic-byte detection | `image_util.rs`: `image` crate (+ optional `webp`) |
| WebP | `uwebp.pas` — dynamic libwebp FFI (`libwebp.so.*`, encode/decode) | `image_util.rs` (no dynamic load — bundled crate) |
| CBR/RAR | `uarchive.pas` + `uzipeditor.pas` — libarchive dynamic load, two-pass scan | `cbr_reader.rs` / `cbr_convert.rs` — libarchive via `libloading`, same two-pass |
| Parallelism | LCL `TThread` worker pools (WebP/validate cap 8; CBR cap 4) | `rayon` pools (same caps: 8 for WebP/validate, 4 for CBR) |
| XML (`ComicInfo.xml`) | `ucomicinfo.pas` (FCL DOM + UNSET sentinels) | `comicinfo_xml.rs` / `comicinfo.rs` (`quick-xml`) |
| Settings | `usettings.pas` INI (`GetAppConfigDir`) | `confy` / `tauri-plugin-store` |
| Logging | `ulog.pas` thread-safe file logger; observer → job monitor | `logger.rs` (tracing) — **but inert in GUI, see bug L/T-share-4** |
| Threading model | progress via `TThread.Queue`; documented Synchronize/FreeOnTerminate use-after-free hazard | Rust async + Tauri event emitter (`Emitter::emit`) |
| Tests | 25 FPCUnit files (~7046 lines), `make test` (offscreen) | Rust integration tests in `rust-core/tests/` (~54 #[test]), `cargo test` |

---

## 3. Feature parity table (incl. GUI)

✅ = implemented & wired  ⚠️  = exists but with known issue  ❌ / 🔴 = missing/empty

| Feature | Lazarus | Tauri port | Notes |
|---|---|---|---|
| CLI `validate [--threads N]` | ✅ (`uclimode.pas`) | ✅ (`cbzmanager-cli`) | parity; exit codes 0/1/2 in both |
| CLI `convert-webp [--delete/--threads N]` | ✅ | ✅ | **shared quality bug** ⚠️ (see §5) |
| CLI `merge [--delete --force --chapters [--chapters-per-volume]]` | ✅ | ✅ | divergences documented in AGENTS.md / PLAN.md |
| CLI `cbr-to-cbz [--delete/--threads N]` | ✅ | ✅ | **shared CLI exit-code bug** ⚠️ (`uclimode.pas:485`; Rust mirrors) |
| Headless CLI dispatch & flags before/after dir | ✅ | ✅ | both mirror Python argparse tolerance |
| Validate (quick + deep, per-file decode pool) | ✅ | ✅ | parity |
| Convert-to-WebP (only-if-smaller, filter+renumber, backup) | ✅ | ✅ | **shared WebP quality bug** ⚠️ |
| Merge (classification, CPV real division, batching, force, chapter ranges) | ✅ | ✅ | Rust uses `zip` crate + rayon; parity intended |
| ComicInfo scan / remove / view / edit / generate | ✅ (`udlgcomicinfo`, `udlgcomicinfoeditor`) | ✅ (`cmd_scan_comicinfo`, `cmd_remove_comicinfo`, ComicInfoDialog.svelte) | shared comicinfo ghost-entry quirk ⚠️ |
| CBR→CBZ batch (skip-existing, delete-source) | ✅ | ✅ | both degrade gracefully when libarchive absent |
| In-place page editor (delete/reorder/sort/reverse/renumber, stage bar) | ✅ (`udlgpageeditor`, `upageeditmodel`) | ✅ (`PageEditor.svelte`, `page_model.rs`, `StageBar.svelte`) | **renumber padding divergence** ⚠️ |
| Batch edit dialog (percent resize, colour, split lines) | ✅ (`udlgbatchedit`) | ✅ (`BatchEdit.svelte`, `batch_edit.rs`) | Rust uses only first page's cut-lines + hardcoded horizontal ⚠️ |
| Sequence builder / merge preview | ✅ (`udlgseqbuilder`) | part of MergeDialog (per TARGET.md) | most complex dialog in both |
| Job monitor (non-modal progress + log) | ✅ (`ufrmjobmonitor.pas`) | ✅ (`JobMonitor.svelte`) | Rust `logger.rs` module is inert ⚠️ |
| Full-res page viewer (Space key) | ✅ (`udlgpageview`) | ✅ (`PageViewer.svelte`) | parity |
| Directory / file-browser two-pane UI | ✅ (`main.pas`) | ✅ (`App.svelte`, `FileBrowser.svelte`) | both implemented |
| Thumbnail lazy-loading w/ stale-batch epoch guard (Lazarus) / sliding-window ack (Tauri) | ✅ (`uloaderthread.pas`) | architecture in TARGET.md; batched loading planned | threading model differs (Queue vs events) |
| Settings persistence dialog | ✅ (`usettings.pas`) | ✅ (`stores/settings.ts`, `load_settings`/`save_settings`) | parity |
| Keyboard shortcuts (F4/F5/F8, Ctrl+S/Ctrl+A, Space, Del) | ✅ | planned in TARGET.md §Phase 3 ⚠️ | **not confirmed wired** — verify against `App.svelte` |

**Headline verdict:** the Rust core + CLI match Lazarus feature-for-feature. The main gap is not "missing core ops" but **GUI parity completeness details** (some shortcuts, per-page split geometry) and **documented-vs-actual GUI status mismatch**.

---

## 4. GUI deep-dive (the user explicitly asked about GUI)

### Lazarus GUI (LCL)
- Two-pane `TfrmMain` (`main.pas`): left file browser `LVFiles` (first-page thumbnails), right page pane `LVPages`.
- Heavy I/O on background threads (`TLoadThread`, `TPagesThread`, `TSaveChangesThread`, service threads); progress via `TThread.Queue`. Page-edit model in `upageeditmodel.pas` with `FPages`/`FBaseline`/`FChanges`, stage bar when pending.
- Dialogs: LCL `.lfm`-defined forms (validate, webp, cbr, merge, comicinfo editor/view, pageeditor, pageview, seqbuilder, rows, convertresults). Job monitor is non-modal floating (`ufrmjobmonitor.pas`).

### Tauri GUI (Svelte 4 + TS)
- Frontend: `web/src/App.svelte` orchestrates `FileBrowser`, `PagePreview`, `StageBar`, `BatchEdit`, `PageViewer`, and 5 operation dialogs (`ValidateDialog`, `ConvertDialog`, `MergeDialog`, `CbrDialog`, `ComicInfoDialog`) + `JobMonitor`. Stores: `stores/{files,pages,progress(settings)}.ts`; IPC wrapper `lib/api.ts`.
- Backend: **17 registered commands** (`src-tauri/src/lib.rs:15-38`): archive {list_entries, read_entry, first_image}, directory::list_directory, settings {load_settings, save_settings}, validate {cmd_validate, cmd_validate_deep}, convert_webp, merge, cbr_to_cbz, comicinfo {cmd_scan_comicinfo, cmd_remove_comicinfo}, page_edit {page_load, page_save}, batch_edit.
- **Permissions:** `capabilities/default.json` grants only `core:default`; heavy ops are pure server-side `std::fs` (never typed IPC), so no fs/path capability needed — correct trade-off.
- **Status vs docs:** Despite PLAN.md marking checkpoint 6 "🔴 Empty scaffold", the GUI is **substantially implemented** — all five operations resolve through the API wrappers to backend commands; page-edit + batch-edit + stage bar + job monitor are wired. **Reconcile PLAN.md with reality.**

---

## 5. Bug hunt

### 5A. Lazarus bugs (verified in `src/`)

| # | Location | Issue | Severity |
|---|---|---|---|
| L1 ✅fixed | `userviceconvert.pas:126,147` | `Modified` is filled by `ConvertCBZToWebP` as an out-param but **never read** by `TConvertService.Convert`. The "was the file actually changed" flag is computed and discarded — dead output / half-baked feature (success is driven solely by `ConvertedCount`). **Fixed:** Convert now writes whenever `(ConvertedCount > 0) or Modified`, so renames-only / ComicInfo-strip-only passes are persisted; regression test `Convert_RenamesOnly_StillWrites`. | ⚠️ low-med |
| L2 | `uservicevalidate.pas:201,203-209` | **Zero-entry batch** → sets `Valid := TotalValid > 0` and returns invalid reason `"All images failed to decode"` instead of reporting an empty CBZ as *valid*. Diverges from the Python reference (empty = valid). | ⚠️ med (parity/correctness) |
| L3 | `userviccomicinfo.pas` (~255) | Removing `ComicInfo.xml` from an archive that has ComicInfo **but no images** leaves a non-empty zip with one ghost entry, reported as `Removed=true / total 0`. Produces an effectively invalid CBZ silently. | ⚠️ med |
| L4 ✅fixed | `uclimode.pas:485` | CBR convert path exit code. Correction on capture: the libarchive-missing guard **already** exited `EXIT_ERROR` (uclimode.pas:442) — the real gap was that per-file hard failures landed in the "skipped" bucket with `Result := EXIT_OK`. **Fixed:** failures now print to stderr and force exit 1 (`Summary: ... Failed: N`); skip-existing remains a benign exit 0. Rust CLI mirrored. Test: `RunHeadless_CbrToCbz_FailedFileExitCode`. | ⚠️ med |
| L5 (stale) | AGIT.md/AUDIT "CRITICAL corrupted sort in `uzipeditor`" (`FindIndexToInsertPage`) | **Does NOT reproduce.** Current code captures `Key := SortedNames[i]` *before* the shift loop — correct insertion semantics. AUDIT claims describe a pre-fix version. Marked here as resolved/stale to avoid false alarms. | n/a (disproven) |

**Threading hazard (documented, untested):** `uthreadservice.pas:306` uses `Synchronize`; the code comments warn that combining this with `FreeOnTerminate := True` can SIGSEGV via a self-freeing thread's queued stream. Descendants set `FreeOnTerminate := False`, but there is **no regression test** covering the hazard — it relies on discipline, not enforcement.

### 5B. Tauri-port bugs (verified in `porting/tauri/`)

| # | Location | Issue | Severity |
|---|---|---|---|
| T1 | `cbr_reader.rs:240-241` | `let size = (symbols.entry_size)(entry_ptr) as usize;` then `Vec::with_capacity(size)`. libarchive's `archive_entry_size` returns **`-1` for unknown entries**; casting `-1 i64 → usize` → huge capacity ⇒ **OOM/panic on malformed RARs**. Memory-safety-relevant. | ⚠️⚠️ high (crash) |
| T2 ✅fixed | `page_model.rs:218-223, 241-242` | Renumber used `page_padding_for(visible_count()) + 1` and `insert_at` hardcoded `{:04}` — the in-place editor renamed pages **one zero-digit wider** than other paths. **Fixed:** both now use the fixed `PAGE_PAD_DEFAULT` (=4), matching Pascal `upageeditmodel.PageRenumber` exactly (Pascal's editor is pad-4 by design; convert/cbr keep their own count-derived rule). Tests: `renumber_uses_fixed_editor_padding`. | ⚠️ low-med |
| T3 ✅fixed | `commands/batch_edit.rs:86,97` | Batch edit took only the first page's cut-lines (`params.cut_lines.first()`) and hardcoded `horizontal_lines = true`. Correction on capture: Lazarus batch edit is **uniform** too (one line set + one direction flag for all pages, `ubatchedit.pas`), so per-page geometry was never a Lazarus feature — but the vec-of-vec wire shape silently dropped everything but page 1. **Fixed:** IPC params are now flat `cut_lines: Vec<f64>` + explicit `horizontal_lines` (serde default true); Svelte dialog gained a Horizontal/Vertical radio mirroring `udlgbatchedit`'s direction group and a "N lines → N+1 pieces" hint. | ⚠️ med |
| T4 ✅fixed | `logger.rs` defined, **inert** | Dead module removed (it wasn't even declared in `commands/mod.rs`). JobMonitor's log stays progress-event-driven, as designed. | ⚠️ low |
| T5 | `convert_webp.rs:190-192` / `image_util.rs` | Passes `WEBP_QUALITY` (75) to `encode_image`, but the WebP encode branch ignores it (`buffer.write_to()` with no quality param). The caller's quality math is **dead**; output quality is fixed regardless. Shared with Lazarus L1. | ⚠️ low-med (parity bug) |
| T6 | `PLAN.md` checkpoint 6 vs code | Docs say GUI is empty scaffold; actual GUI is substantially complete. Not a code bug but causes confusion/mis-triage for future contributors. | n/a (doc drift) |

### 5C. Shared / parity bugs (present in BOTH, worth comparing/fixing together)

| Bug | Lazarus ref | Tauri ref | Description |
|---|---|---|---|
| WebP quality ignored | `uimgutil.pas` / `IntfImageToWebP q75 default` (`uwebp.pas:30-32`) | `convert_webp.rs:190` / `image_util.rs` | "Quality 75" is effectively fixed/hardcoded in both; the quality setting isn't actually applied by the encoder. Same latent bug carried across the port. |
| CBR CLI exit code not propagated | `uclimode.pas:485` | Rust `cbzmanager-cli` mirrors | Failure to return nonzero on libarchive-missing in CBR path. |
| Ghost/empty archive reporting | `uservicevalidate.pas` (empty→invalid) / comicinfo ghost entry | Rust core likely parallels (same port of same logic) | Empty/ComicInfo-only archives reported with surprising valid/invalid status. Reconcile both against the Python golden model. |

---

## 6. Test coverage comparison

| Dimension | Lazarus | Tauri port |
|---|---|---|
| Suite size | **25 FPCUnit files** (~7046 lines) — AGENTS.md wrongly says "13" | ~54 `#[test]` across 9 files in `rust-core/tests/` + integration tests |
| Determinism tests (parallel threads 1 vs 4 → byte-identical) | ✅ (`test_uzipeditor`, `test_userviceconvert`, `test_uservicevalidate`, `test_uservicecbr`) | partial — one WebP determinism test at `tests/convert_webp.rs:44`; does **not** exercise the quality path (would pass despite T5 bug) |
| Merge depth | ✅ deepest (`test_uservicemerge.pas`, 1337 L) | present (`tests/merge.rs`, 6 tests) |
| CLI dispatch/exit codes | ✅ thorough (`test_uclimode.pas`, 543 L) | present in `cbzmanager-cli` integration tests |
| Page model (Data precedence, renumber) | ✅ (`test_upageeditmodel.pas`) | ✅ (`tests/pagemodel.rs`) but **renumber padding not covered** (T2 gap) |
| CBR reader | ✅ walking/decoding/conversion (+ real-RAR guard) | ✅ `tests/cbr_reader.rs` (4 tests) — **but no malformed-entry / size-casting test** (T1 gap) |
| Dialog logic | partial — 3927 lines of `udlg*.pas`, only logic-bearing ones tested | dialogs are Svelte (no unit tests at all — E2E would cover, none yet) |

**Notable gaps:**
- Lazarus: **no regression test** for the documented `Synchronize`+`FreeOnTerminate` SIGSEGV hazard (`uthreadservice.pas:306`); relies on convention.
- Tauri: **no coverage** of T1 (OOM), T2 (renumber padding), or the quality path (T5). Svelte GUI has zero automated tests (only planned Playwright/tauri-driver E2E).

---

## 7. Prioritised recommendations

1. **Fix T1 (`cbr_reader.rs:240`) now** — OOM/panic on malformed RAR is the single highest-severity issue; guard `size` against `< 0`.
2. **Reconcile docs vs reality** in `porting/tauri/PLAN.md` (checkpoint 6) — GUI is implemented, not an empty scaffold. Prevents future mis-triage.
3. **Fix L4 / Rust mirror**: propagate nonzero exit when libarchive missing on CBR convert CLI path.
4. **Reconcile empty-archive validity** (`L2`) and ComicInfo ghost-entry handling (`L3`, T-par) with the Python reference as the single source of truth; add parity tests in BOTH suites so neither drifts again.
5. **Decide the renumber padding divergence** (`T2` vs Lazarus `uzipcore.pas:FormatPageName`) — standardise on one zero-padding rule across all operations (convert/merge/cbr/in-place).
6. **Batch-edit per-page split geometry** — lift the `first()` limitation + hardcoded horizontal flag (`T3`) to match Lazarus, or document it as an intentional limitation.
7. **Wire Rust trace logging** into the JobMonitor (`T4`) or remove the inert `logger.rs`; and **confirm keyboard-shortcut parity** (`App.svelte`) against the LCL shortcuts listed in TARGET.md Phase 3.
8. **Add regression tests**: T1 OOM path; L5 threading hazard; parity determinism including quality path.

---

## 8. Open questions (for the user)

- Is the Tauri GUI actually *usable/deliverable* at this point, or only function-wired? Recommend a manual smoke test of each dialog.
- Should the two ports be kept feature-synchronised (add a differential test harness: same fixture → identical output archive), given shared bugs drift independently?
- Intended WebP quality: expose a real quality flag (both currently fixed) or accept q75 as constant?

## 9. Fix plan

Ordered by severity/value. Each item lists the concrete change, where to make it, and how to verify (add/extend a test in the relevant suite). Shared bugs are fixed together in **both** ports with an added differential parity test so neither drifts again. Task-tracking prefixes match repo commit style (`fix(tauri)` / `fix(lazarus)` / `fix(core)`).

### P0 — crashers (fix first)

- **[T1] CBR entry-size OOM/panic** — `porting/tauri/rust-core/src/cbr_reader.rs:240`
  - Change: guard the cast so `-1` (unknown size, per libarchive docs) never becomes a huge usize capacity.
    ```rust
    let raw = (symbols.entry_size)(entry_ptr);
    if raw < 0 { /* unknown — treat as no data, do not pre-allocate */ use zero_len(); }
    let size = raw.max(0) as usize;
    ```
  - Verify: new `tests/cbr_reader.rs` case synthesizing an RAR entry whose size is `-1`; assert the reader returns empty/None instead of panicking/OOMing.
- **[L5] STALE — already resolved** — `src/uthreadservice.pas` (Synchronize at ~349; line 306 in the plan predates a refactor)
   - Status: **Do not change.** Progress() *used* `TThread.Queue` + `FreeOnTerminate=True`, which caused the use-after-free SIGSEGV in `SyncProgress` and re-raised callback exceptions on the main thread. The code was already migrated to a blocking `Synchronize`: the worker stays alive during the call (object owned by Execute) and any callback exception is passed back into `Execute`'s per-file try/except. Switching back to Queue would **reintroduce** the crash.
   - Verify: `tests/test_uthreadservice.pas` (`Progress_DeliversValuesToMainThread`, `Progress_RaisingCallbackStaysInWorker`) documents + locks this; both pass under `make test`. See also §5a "L5 (stale)" which was already marked disproven.

### P1 — correctness / parity with Python golden model

- **[L2 + T-par] Empty-archive validity** — `src/uservicevalidate.pas` / rust `validate.rs`
  - Change: a batch/archive with **zero entries** returns an "empty" (valid) status, not invalid `"All images failed to decode"`. Fix the empty guard before the `TotalValid > 0` check; mirror in Rust.
- **[L3 + T-par] ComicInfo ghost-entry reporting** — `src/userviccomicinfo.pas` / rust `comicinfo.rs`
  - Change: if removal leaves **no real image entries**, mark result Invalid (total 0 images); skip writing an all-ComicInfo zip. Mirror in Rust.
  - **Status: DONE.** Both ports now guard on image entries *before* writing: strip ComicInfo.xml, and if no surviving entry is an image (`.png/.jpg/.jpeg/.bmp/.gif/.webp/.tiff/.tif`), keep the archive untouched and report it as **skipped** (`Removed=False`, `ErrorMsg="No images to keep"`), leaving `HasComicInfo=True`. In Pascal this lives in `StripComicInfo`-adjacent logic in `uservicecomicinfo.pas:RemoveOne`; the extension check is a headless helper in `uzipcore.pas` (mirrors `uimgutil.IsImageExt`) so services don't drag in the LCL graphics stack. Rust reuses `zip_ops::is_image_entry`.
  - Verify: Pascal `tests/test_uservicecomicinfo.pas` (`Remove_NoImages_Skipped`, metadata-only `.cbz` → skipped, original byte-identical); Rust `porting/tauri/rust-core/tests/comicinfo.rs` (5 cases incl. parallel-vs-sequential and no-backup-on-skip). `make test` = 206 tests / 0 errors; `cargo test -p rust-core --test comicinfo` = 5/5 pass.
- **[L1 + T5] WebP quality ignored** — `src/userviceconvert.pas` (unused `Modified`) / `porting/tauri/{rust-core/src/convert_webp.rs:190, rust-core/src/image_util.rs}`
  - Change A: actually apply the passed quality to the encoder (libwebp `WebPEncodeBGRA` options in Pascal; pass a quality param through in Rust). Fix `IntfImageToWebP`/`encode_image` to honor it.
  - Change B: consume the `Modified` flag in `TConvertService.Convert` instead of discarding it.
  - **Status: DONE.** T5 (Rust quality) landed in commit 2fb37dd; Pascal's `IntfImageToWebP` already honored quality via `WebPEncodeBGRA`. L1 Change B: `TConvertService.Convert` now writes when `(ConvertedCount > 0) or Modified`; regression test `tests/test_userviceconvert.pas:Convert_RenamesOnly_StillWrites` (all-WebP archive + ComicInfo → rewritten, stripped, renumbered).
- **[renumber padding] T2** — `porting/tauri/rust-core/src/page_model.rs:218-242`, cross-check `src/uzipcore.pas:FormatPageName`
  - Change: standardize zero-padding across convert/merge/cbr/in-place editor. Pick one rule (`page_padding_for(count)` without the stray `+1`) and remove the `{:04}` hardcode in `insert_at`.
  - **Status: DONE** (with a corrected rule): Pascal's editor is fixed pad-4 (`PAGE_PAD_DEFAULT`) by design, so the Rust page model now uses `PAGE_PAD_DEFAULT` for both `renumber` and the `insert_at` placeholders — exact parity with `upageeditmodel.PageRenumber` rather than forcing the count-derived rule onto the editor. Test: `tests/page_model.rs:renumber_uses_fixed_editor_padding`.
- **CBR CLI exit code** — `src/uclimode.pas:485` / `porting/tauri/cbzmanager-cli/src/main.rs`
  - Change: propagate libarchive-missing as nonzero exit (`EXIT_RUNTIME = 1`) instead of always `EXIT_OK`.
  - **Status: DONE.** Correction: the libarchive-missing guard already exited nonzero on both sides; what was actually fixed is per-file hard failure propagation (`Success=False` / non-empty `error_msg` → stderr + exit 1; skip-existing stays benign 0). Tests: `RunHeadless_CbrToCbz_FailedFileExitCode` (Pascal); Rust CLI mirrors the same summary/exit logic.

### P2 — GUI / feature parity details

- **[T3] Batch-edit per-page split geometry** — `porting/tauri/src-tauri/src/commands/batch_edit.rs:86,97`
  - Change: iterate per-page cut-lines (drop `.first()`); remove the hardcoded `horizontal_lines = true`. Mirror Lazarus `ubatchedit.pas` per-page staging. Verify against a `test_ubatchedit.pas` parity case.
  - **Status: DONE** (as uniform-lines parity, not per-page): Lazarus batch edit is uniform by design, so the fix flattened the IPC shape to `cut_lines: Vec<f64>` + `horizontal_lines: bool` (serde default) and removed `.first()`/the hardcoded flag; Svelte dialog gained the Horizontal/Vertical direction radio + pieces hint.
- **[T4] Inert Rust logger** — `porting/tauri/src-tauri/src/commands/logger.rs`
  - Decision: either register a `log` command and wire `LogEmitter` into `JobMonitor.svelte`, **or** remove the dead module (preferred if no log panel is intended).
  - **Status: DONE — removed.** The module was unreferenced (not even in `commands/mod.rs`); JobMonitor stays progress-event-driven.
- **[shortcuts] Confirm keyboard-shortcut parity** — `web/src/App.svelte` vs TARGET.md Phase 3 (F4/F5/F8, Ctrl+S/Ctrl+A, Space, Del). Add missing handlers or file a deferred issue.
  - **Status: DONE.** Wired F5 (reload), F8 (validate dialog), Ctrl+S/Cmd+S (save staged changes), Del (mark highlighted page gone), Space (page viewer — already present). Deferred with an inline note in `onKeydown`: F4 preview toggle and Ctrl+A select-all need UI that doesn't exist yet in the webview (no preview pane / multi-select model).

### P3 — docs & hygiene

- **[T6] Reconcile PLAN.md checkpoint 6** — GUI is substantially implemented, not empty scaffold.
  - **Status: DONE.** Checkpoint 6 in `porting/tauri/PLAN.md` now carries an implemented-status note listing the divergences from the original plan.
- **[AGENTS.md test count]** update stale "13 test files" → actual count (25 for Lazarus).
  - **Status: DONE** ("25 FPCUnit files (23 test units + shared helpers + runner)").
- Add a **differential parity harness**: same fixture → compare output archive between Lazarus CLI and Rust CLI (`ZipFilesEqual`-style in Rust) to lock shared behaviors (§8 open question #2) and prevent independent drift.
  - Status: OPEN — deferred; needs a common fixture generator callable from both toolchains.

### Verification matrix (after P0–P1 done)

| Check | Where | Command |
|---|---|---|
| No panic on malformed RAR | `rust-core/tests/cbr_reader.rs` | `cargo test -p rust-core cbr_reader` |
| Determinism threads 1 vs 4 (incl. quality path) | both suites | `make test` / `cargo test` (add fixed-quality determinism case) |
| Empty-archive validity | validate tests both ports | run against empty `.cbz` fixture; assert valid/empty status |
| Renumber width consistency | page-model tests both ports | 9-page file → expect `page_1.jpg` everywhere, not mixed widths |
| CLI exit codes on CBR missing lib | `test_uclimode.pas` / Rust CLI integration | force `libarchive` absent → assert exit == 1 |

### Definition of done
- All P0 crashers fixed + regression tests present.
- All P1 parity bugs fixed and guarded by **tests in both ports** (differential harness passes).
- GUI decisions made for P2 (T4 wired or removed; shortcuts implemented/deferred) with an issue filed for leftovers.
- PLAN.md / AGENTS.md reconciled to actual state.

---
*End of findings and fix plan. Document is iterative — append new verified findings with `file:line` refs below this line.*

---
*End of findings. Document is iterative — append new verified findings with `file:line` refs below this line.*
