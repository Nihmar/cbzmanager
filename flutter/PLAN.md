# Flutter port — Detailed plan

Tracking issue: [Nihmar/cbzmanager#7](https://github.com/Nihmar/cbzmanager/issues/7)
Branch: `porting/flutter`
Architecture: [`TARGET.md`](TARGET.md) · Parity map: [`PARITY.md`](PARITY.md)

---

## 0. Executive summary

Port CBZ Manager to **Flutter** on **Android, Linux and Windows**, preserving the
existing Lazarus/FPC application untouched. The port lives entirely under
`flutter/`.

The plan is **phased**, each phase ending in a running, testable increment:

| Phase | Deliverable | Gate |
|---|---|---|
| 0 | Scaffolding, CI, **pure-Dart/FFI spike**, VFS interface | Go/no-go on pure Dart |
| 1 | Archive browser (local + **SMB**) with thumbnails and preview | Go/no-go on Android/SMB |
| 2 | `validate` + `comicinfo` | — |
| 3 | `convert-webp` | — |
| 4 | `merge` + sequence builder | — |
| 5 | CBR preview + `cbr-to-cbz` | — |
| 6 | Page editor + batch edit | — |
| 7 | Image search ("add image from internet") | — |
| 8 | Settings, Job Monitor, i18n, packaging, CLI | Release |

**Recommended core:** a **pure-Dart engine** (`package:archive` +
`package:image`) with a small `dart:ffi` shim to **libarchive** for CBR/RAR
(ADR-001). A **new** Rust engine via `flutter_rust_bridge` v2 is the fallback if
the Phase-0 benchmark shows the Dart image pipeline is too slow or loses
quality — it is written for this port, not reused from anywhere.

**SMB decision (requirement 2):** Android **stays in scope**. `dart_smb2`
(SMB2/3 on libsmb2) provides prebuilt Android/Linux/Windows binaries and the
whole `Vfs` surface. The port uses a byte-oriented *localize → process → publish*
workspace, which makes SMB (and Android SAF) transparent to every operation.
Detailed analysis in §2; the fallback chain ends at "drop Android, ship
Linux+Windows" if the Phase-1 PoC fails.

---

## 1. Requirements and scope

### 1.1 Functional scope (parity target)

From the Lazarus application:

1. **Archive browser**: list `*.cbz`/`*.cbr`, first-page thumbnails, page preview
   with zoom/pan, read-only CBR pages.
2. **`validate`** (deep, per-file parallel decode; file-level errors surface).
3. **`convert-webp`**: WebP q75, only-if-smaller, filter `ComicInfo.xml`, rename
   survivors `page_NNNN.*`, backup `_OLD.cbz` or delete, parallel.
4. **`merge`**: chapter classification (`Title - NNNN.cbz`, `SPnn`), CPV
   auto/force/custom, volume `VNNN` continuation, rollback on failure, optional
   per-volume `ComicInfo.xml`, sequence-builder UI, parallel volume build.
5. **`remove-comicinfo`**: scan/strip, optional backup.
6. **`cbr-to-cbz`**: RAR→CBZ in RAM, skip-existing, optional delete-source,
   parallel; graceful degradation when libarchive is absent.
7. **Page model + page editor**: delete/move/insert, renumber, resize (aspect
   lock), colour adjustments (invert/grayscale/sepia/RGB gains/saturation/
   contrast/brightness/gamma), split (N cut lines → N+1 pieces), staged until
   save.
8. **Batch page-edit**: uniform resize, colour adjust, split across a selection.
9. **Add image from internet**: search (MangaDex default, plus the other
   providers in `uimgsrc.pas`) or pasted URL, download, insert as first page.
10. **Job Monitor**, progress reporting, settings persistence, logs.
11. **Headless CLI** (optional — see §10 Q3).

### 1.2 Non-functional requirements

- In-RAM archive operations (no page extraction to disk).
- Deterministic output for any thread count.
- Parallel caps: WebP/validate ≤ 8; CBR/merge/batch-edit ≤ 4; `0` = auto.
- Responsive UI during long jobs; cancellable.
- Offline-capable except image search.
- Reference-compatible naming and ordering (byte-wise sort, not locale).

### 1.3 Out of scope

- `find-similar`, `delete-pages-by-id`, batch `delete-pages` (already out of
  scope in the reference port — covered by the in-place editor).
- Rewriting RAR (CBR stays read-only; conversion is the edit path).
- iOS/Web (may fall out of Flutter for free, but are not targets).

---

## 2. SMB on Android — feasibility study and decision

### 2.1 Candidate approaches

| Approach | SMB versions | Platforms | Native build | Verdict |
|---|---|---|---|---|
| **`dart_smb2`** (libsmb2 via FFI) | 2/3 | Android arm64/armv7/x86_64 (API 24+), Linux x86_64/aarch64, Windows x86_64/arm64, macOS, iOS | prebuilt, SHA-256 pinned, downloaded per target | **chosen** |
| `smb_connect` (pure Dart) | 1.0, CIFS, 2.0, 2.1 | all Dart platforms | none | fallback; no SMB3 |
| Android platform channel + `smbj` (Java) | 2/3 | Android | Kotlin only | fallback; most code |
| Android SAF + an SMB `DocumentsProvider` | depends | Android | none | not self-contained (needs a third-party provider) |
| OS-mounted share | native | Linux/Windows | none | already handled by `LocalVfs` |
| Rust `smb`/`pavao` crate | 2/3 | all | Rust | only relevant if Option B (new Rust engine) is chosen |

### 2.2 Why this is not "too complex"

The application's operations consume **whole archives as byte buffers** (the
in-RAM rule). Therefore the network layer only needs: `list`, `stat`, `readAll`,
`writeAll`, `rename`, `delete`, `mkdir`. `dart_smb2` supplies exactly these
(plus streaming, range reads, chunked writes and reconnection). No random-access
SMB filesystem, no kernel mount, no FUSE is required.

The `Workspace` (§TARGET 5) downloads a source archive into the app cache,
runs the engine, and writes the result back atomically. Backups, output naming
and cleanup are expressed through the same `Vfs` calls used for local files, so
**every operation works unchanged over SMB**.

### 2.3 Decision

- **Keep Android in scope.**
- Implement `SmbVfs` (ADR-004) behind the `Vfs` interface.
- Credentials in `flutter_secure_storage`; support guest, NTLMv2, domain, and
  custom port; store connection profiles (host/share/user, never the password in
  plain settings).
- Provide an SMB connection management screen (list profiles, test connection,
  browse shares).
- Vendor/sha-pin the libsmb2 binaries (CI artifact or an internal release) so the
  build does not depend on a third-party GitHub Release at build time.
- **Phase-1 PoC gate:** on a real device/emulator, against a Samba server:
  list a share, download a CBZ, convert it, upload the result, verify by
  re-download. If the PoC fails within its timebox, execute the fallback chain;
  if all fallbacks fail, **drop Android** and ship Linux + Windows.

### 2.4 Security and robustness

- TLS is not applicable to SMB; prefer SMB3 encryption when the server supports
  it; refuse SMB1 (libsmb2 enforces SMB2+).
- Never log credentials; redact in error paths.
- Handle disconnects mid-job: `dart_smb2` worker pool exposes reconnect; a failed
  upload leaves the previous file intact (atomic temp+rename).
- Path traversal: normalise share-relative paths; reject `..` escaping the share.

---

## 3. Architecture (summary)

See [`TARGET.md`](TARGET.md) for the full ADR. In brief:

- **UI** (Flutter, Material 3, Riverpod, go_router, adaptive shell).
- **Controllers** per feature, one **Job** abstraction, streamed progress.
- **Engine** pure Dart (recommended) or a new Rust engine via FRB; byte-oriented facade.
- **VFS** local / SAF / SMB / memory, with a localize→publish workspace.

---

## 4. Phased roadmap

Estimates are ideal engineer-days (one developer, familiar with Flutter); they
exclude review latency. Range = optimistic…pessimistic.

### Phase 0 — Foundations and spike  *(4–7 d)*

**Status: complete.** Pure-Dart engine + libarchive FFI accepted (ADR-001);
app builds on Linux and Android.

**Goal:** a building, tested shell on all three platforms and a decision on the
engine architecture.

Tasks
- [x] `flutter create` in `flutter/app` (org `app.cbzmanager`, platforms:
      android, linux, windows).
- [x] Repo hygiene: `flutter/` tracked (root `.gitignore` re-includes
      `flutter/app/lib`, which the FPC `lib/` rule was hiding).
- [x] App skeleton: minimal `CbzManagerApp` shell with an engine self-test.
- [x] Define `CbzEngine` facade (`TARGET.md` §4) and `Vfs` interface (`§5`) with
      `MemoryVfs` + `LocalVfs` implementations and a `Workspace`.
- [x] **Pure-Dart engine spike:** `archive` + `image` validate / convert-WebP /
      ComicInfo scan+strip round-trip (32 tests green).
- [x] **libarchive FFI spike:** `Libarchive`/`CbrReader` read zip-format CBR
      fixtures on Linux; graceful degradation when the library is missing.
- [ ] Bundle `libarchive` for Android ABIs and verify CBR on a device/emulator.
- [x] ADR-001 decided: pure Dart, with a new Rust engine as fallback only.
- [ ] CI skeleton: GitHub Actions (ubuntu/windows), `flutter analyze` + `flutter test`,
      Android debug APK job.
- [ ] Set `minSdk 24` + explicit ABI filters in the Android Gradle config.

**Verified:** `flutter analyze` clean; `flutter test` 32/32; `flutter build linux
--debug` OK; `flutter build apk --debug` OK.

**Definition of done**
- `flutter run -d linux` and `flutter run` on an Android emulator both launch the
  empty shell.
- `flutter test` passes in CI (plus Rust tests if Option B is chosen).
- Engine decision recorded; the facade is implemented by at least one backend.

**Risks:** pure-Dart image perf/quality and libarchive ABI builds → mitigate with the new-Rust-engine fallback.

---

### Phase 1 — VFS, SMB PoC and archive browser  *(8–14 d)*

**Goal:** browse a folder (local and SMB), show first-page thumbnails, open a page
preview. This phase proves requirement 2 end-to-end.

Tasks
- [x] `MemoryVfs` (tests) and `LocalVfs` (desktop/local paths); Android SAF
      tree-URI access still to do.
- [x] `SmbVfs` on `dart_smb2`: connect, list/dir, stat, read/write, rename,
      delete, mkdir (connection profile model + secure storage still to do).
- [x] `Workspace`: in-RAM localize/publish, atomic write, `_OLD.cbz` backup.
- [x] **SMB PoC gate** against a Samba container: VFS round-trip and a full
      engine `validate` + `convert-webp` + publish round-trip pass on Linux.
- [x] Thumbnail loader: bounded read + decode pools (`Isolate.run`), small
      JPEG cache, first-page decode on a background isolate.
- [x] Browser UI: archive grid with thumbnails, byte-wise sort, loading/empty/
      error states, source menu (local folder + SMB dialog). Multi-select,
      context menu and drag-and-drop still to do.
- [x] Page preview: immersive `PageView` with `InteractiveViewer` zoom + a
      thumbnail rail, page counter, read-only badge for CBR.
- [ ] Verify SMB on an Android device/emulator (bundle libsmb2 per ABI).
- [x] Widget tests for the browser grid + preview data path; unit tests for the
      browser controller, thumbnails and `MemoryVfs`/workspace (38 green).
- [ ] Android SAF tree-URI access for local folders.

**Definition of done**
- On Android (device/emulator) a user can add an SMB share, browse it, open a CBZ,
  page through thumbnails and preview a page.
- On Linux and Windows the same flow works against a local folder and a mounted
  SMB path (SmbVfs optional).
- Thumbnails are generated off the UI thread; cancelling/changing folder leaves
  no leaked workers or stale items.

**Gate:** if SMB PoC fails → fallback chain → possibly drop Android.
**Gate status (Linux): passed** — `SmbVfs` + `Workspace` + engine round-trip are
verified against a live Samba container (`CBZ_SMB_TEST=1`). Android device
verification is still pending (`libsmb2.so` must be bundled per ABI).

---

### Phase 2 — Validate + ComicInfo  *(5–8 d)*

**Status: complete** (engine + services + UI; parallel decode still sequential).

- [x] Engine: `validate` (deep, per-image checks) and ComicInfo read/write/
      strip in the Dart engine.
- [x] ComicInfo parser/generator ported from `ucomicinfo.pas`
      (`ComicInfo.parse`/`toXml`, escaping, unset sentinels, XML round-trip).
- [x] `validate` feature: single and multi-file scope, results dialog with
      per-file/per-image errors and a copyable report.
- [x] `comicinfo` feature: scan report, remove with optional `_OLD` backup,
      and the ComicInfo viewer/editor (create when absent).
- [x] Progress + cooperative cancellation through the Job model, shown as an
      app-bar progress bar in the browser.
- [x] Browser multi-selection (long-press / select-all) with batch actions.
- [x] Tests: ComicInfo round-trip, validate/comicinfo services, Job controller
      (51 green). Parallel per-image decode left for a later performance pass.

**DoD:** parity with the reference for validate/comicinfo, including file-level
error surfacing and the threads cap.

---

### Phase 3 — Convert to WebP  *(5–8 d)*

**Status: complete** (parallelism is file-level; per-image decode stays sequential).

- [x] Engine `convertWebp`: q75, only-if-smaller, ComicInfo filter, renumber
      `page_NNNN.*` (sync core `convertWebpSync` is isolate-safe).
- [x] `ConvertService`: converts files concurrently on isolates (0 = auto,
      capped at 8) with progress + cancellation; deterministic per file.
- [x] Feature UI: options dialog (backup vs delete, parallel files) and a
      results summary (pages converted/kept, bytes saved, failures); batch and
      single-file entry points.
- [x] Workspace integration: backup `_OLD.cbz` or overwrite in place, over the
      same Vfs used for local and SMB.
- [x] Tests: encode/rename, backup vs delete, thread-count determinism and
      per-file error isolation.
- [x] Fixed a real isolate bug: `Isolate.run` closures created inside
      `Pool.withResource` captured the pool and threw at runtime (now top-level
      isolate wrappers), with a regression test for the thumbnail service.

**DoD:** a folder batch conversion produces archives byte-identical to the
reference for identical inputs (excluding timestamps).

---

### Phase 4 — Merge + sequence builder  *(8–12 d)*

**Status: complete** (sequence builder is chapter-list based, not a thumbnail grid).

- [x] Engine `merge`: strict classification (`V`, `-`, `_OLD`, decimals, specials),
      Python-exact CPV `(lowest-1)/volumes`, numbering continuation, force,
      chapters list, chapters-per-volume, rollback, optional per-volume ComicInfo.
- [x] `BuildVolumeBytes`: images only, byte-wise sort, renumber `page_NNNN.*`,
      empty batch → no volume.
- [x] `MergeService`: concurrent volume build on isolates (0 = auto, cap 4) with
      progress + cancellation, rollback of partial writes, `_OLD` backup/delete
      cleanup guarded by re-classification.
- [x] Merge dialog: series, chapter range, CPV auto/manual, force, ComicInfo,
      backup/delete, threads and a live volume preview.
- [x] Sequence builder: chapter list with `Vol.N` labels, add/undo/clear,
      preview via `customSequenceLabels`.
- [x] Tests: classification, CPV, specials, force, overflow, resume after existing
      volumes, backup/delete, thread-count determinism (78 green).
- [x] **Bug fix (documented divergence):** the reference preview checked a batch's
      fit on every row and could show `-` where the merge itself succeeds; the
      port checks only at batch start so the preview matches the merge.
- [ ] Multi-series auto-run (currently one dialog run per series, chosen by the
      user) — deferred.

**DoD:** parity with the documented merge divergences (see the reference
AGENTS notes) and a working sequence builder.

---

### Phase 5 — CBR and `cbr-to-cbz`  *(6–10 d)*

**Status: complete** (Android per-ABI bundling still pending).

- [x] Engine CBR: read via libarchive (dynamic load + graceful degradation),
      list/read entries; thumbnails and page previews already route `.cbr`
      through it.
- [x] CBR preview (read-only) feeding the browser/preview from Phase 1, with a
      read-only badge and no page operations.
- [x] `cbr-to-cbz` engine: drop ComicInfo/non-images, renumber `page_NNNN.*`
      (padding via `pagePaddingFor`), write DEFLATE CBZ.
- [x] `CbrConvertService`: folder/batch scope, skip-existing, delete-source,
      threads (0 = auto, cap 4), progress + cancellation, per-file error
      isolation, deterministic output, libarchive-missing degradation.
- [x] Tests: pure renumbering, zip-format `.cbr` conversion, skip-existing,
      delete-source, imageless error, thread-count determinism, thumbnail isolate.
- [ ] Bundle `libarchive` for the Android ABIs and verify on a device/emulator.

**DoD:** CBR archives preview and convert; missing libarchive degrades exactly
like the reference.

---

### Phase 6 — Page model, page editor, batch edit  *(10–16 d)*

**Status: complete** (equal-size split; no draggable cut lines / drag-and-drop yet).

- [x] Dart page model mirroring `TPageState`/`TChange`/`TPageEditModel`:
      delete/move/insert, renumber (`PAGE_PAD_DEFAULT`), edited bytes precedence,
      baseline/revert, change log, deleted-name tracking so removed entries are
      not re-added as metadata.
- [x] `buildEditedArchive`: page order, edited/inserted data, leftover entries
      (ComicInfo.xml) preserved, an original entry claimed at most once.
- [x] Image ops ported from `uimageedit.pas`: box-filter resample, the full
      colour pipeline (invert/grayscale/sepia/gains/saturation/contrast/
      brightness/gamma) and parallel-line split; encode per `EncodeExtFor`.
- [x] Page editor dialog: resize with aspect lock, colour controls + live
      preview, split (rows/columns, N lines → N+1 pieces), original format.
- [x] `PageEditScreen`: page grid, select, delete, move, renumber, edit, and a
      staged "Save changes"/"Revert" bar (save writes via `Workspace` + backup).
- [x] Batch edit: uniform resize %/colour/split across a selection, first-page
      preview, concurrent per-file isolates, backup, renumber; CBZ only (CBR is
      read-only).
- [x] Tests: resample/colour/split, model semantics, save/load with metadata
      preservation, batch resize/grayscale/split and neutral no-op (111 green).
- [x] Drag-and-drop page reordering (`ReorderableListView` + drag handle).
- [x] Draggable split cut lines in the page editor: tap the preview to add a
      cut, drag to move, long-press to remove (explicit cut fractions in the
      pipeline, not just equal slices).
- [ ] Zoomable page grid — deferred.

**DoD:** the single-file editor supersedes the reference's delete/renumber use
case; batch edit matches the reference pipeline.

---

### Phase 7 — Image search / add image from internet  *(4–7 d)*

**Status: complete for a first provider set** (MangaDex, Openverse, Wikimedia, URL).

- [x] Offline-testable parsers ported from `uimgsrc.pas`: `parseOpenverseResults`,
      `parseWikimediaResults`, `parseMangaDexSeries`, `parseMangaDexCovers`,
      `guessExtFromURL` (with `ImageResult`/`MangaSeries` models).
- [x] `ImageSearchService` over `package:http` (descriptive User-Agent):
      MangaDex two-stage series→covers (default), Openverse, Wikimedia, and a
      pasted-URL provider; downloads capped at 20 MB.
- [x] `AddImageDialog`: provider dropdown, query, results grid with network
      thumbnails and titles, download with progress and error UX.
- [x] Wired into the page editor: "Add image from internet" inserts the
      downloaded bytes as a new first page (staged in the page model).
- [x] Tests: parser fixtures for all four providers, `guessExtFromURL`,
      error/invalid-JSON paths (118 green).
- [x] All reference providers: Open Library, Art Institute of Chicago, The Met
      (two-stage), Cleveland Museum of Art, Wellcome Collection and NASA Images,
      plus an 'All sources' fan-out that skips a failing source.
- [x] Tests: parser fixtures for every provider (15 image-search tests).

**DoD:** parity with the reference "add image from internet" flow.

---

### Phase 8 — Settings, Job Monitor, i18n, packaging, CLI, release  *(8–14 d)*

**Status: settings, job monitor and i18n scaffolding done; packaging scripted;
CLI and signed store artifacts deferred.**

- [x] Settings store (`shared_preferences`) + settings dialog: theme mode,
      language, per-operation default threads, backup-by-default. Persisted and
      applied (theme/locale live, thread/backup defaults as dialog initial values).
- [x] Job Monitor: rolling log + elapsed time in the [JobController], a
      non-modal bottom-sheet monitor opened from the progress bar, with cancel.
- [x] i18n: `flutter_localizations` + gen-l10n, `app_en.arb` / `app_it.arb`,
      localized app title, welcome screen and empty state; the remaining strings
      are a mechanical follow-up.
- [x] Packaging: `scripts/build_release.sh` builds the host release (Linux
      bundle + optional APK/AAB, Windows, macOS) after analyze + tests.
- [x] Docs: `flutter/app/README.md` (layout, run/test, SMB tests, release) and
      the parity checklist in `PARITY.md`.
- [x] CI: `.github/workflows/flutter.yml` (analyze + test; Linux release
      bundle; Android debug APK).
- [ ] Signed store artifacts (Play AAB, AppImage/deb, Inno installer) and
      signed CI releases.
- [ ] Headless CLI in Flutter (Q3) — **done** as `bin/cbzmanager.dart`
      (`validate`, `convert-webp`, `merge`, `cbr-to-cbz`; exit codes 0/1/2; runs
      under plain `dart run`, no Flutter). The reference's `comicinfo`
      subcommand and the man page are not ported.
- [ ] Full ARB coverage, accessibility pass and desktop keyboard shortcuts.

**Parity statement:** the port implements the full functional scope (browser +
preview, validate, convert-webp, merge + sequence builder, cbr-to-cbz, ComicInfo
view/edit/remove, page model + editor, batch edit, image search) on a pure-Dart
engine with libarchive (CBR) and libsmb2 (SMB) as the only native dependencies.
Known gaps: Windows packaging/signing not produced here; Android libarchive
bundling; some reference image-search providers; draggable split lines; full
localization. See `PARITY.md` for the per-unit status.

**DoD:** installable artifacts on all three platforms built by CI, with a parity
statement against the reference.

---

## 5. Milestones

| Milestone | Contents | Target |
|---|---|---|
| M0 | Phase 0 done; engine decided | end of week 1–2 |
| M1 | Phase 1 done; Android+SMB proven | week 3–4 |
| M2 | Phases 2–3 done (validate/convert) | week 5–6 |
| M3 | Phases 4–5 done (merge/CBR) | week 7–9 |
| M4 | Phases 6–7 done (editors/search) | week 10–12 |
| M5 | Phase 8 done (release) | week 13–15 |

Total: **~58–96 ideal engineer-days** (≈ 12–18 calendar weeks solo).

---

## 6. Testing strategy (detail)

### 6.1 Layers

1. **Pure unit** (Dart): VFS implementations, workspace localize/publish/backup,
   sort order (`compareStr` semantics), result mapping, page model, settings
   migration, image-search parsers.
2. **Rust engine** (only if Option B): mirror the reference scenarios;
   determinism per thread count; fixtures generated at test time (no binaries
   committed).
3. **Widget/golden** (Flutter): browser grid, preview, editor, dialogs, Job
   Monitor; a few golden images for the empty/loaded states.
4. **Integration** (Dart + native): full operation round-trips on temp dirs.
5. **SMB integration**: a Samba container; list/stat/read/write/rename/delete and
   a full convert/merge round-trip; reconnection and auth-failure cases.
6. **Cross-platform smoke**: Linux/Windows builds + Android emulator app launch
   and one operation.
7. **Differential parity**: generate fixture archives, run the Lazarus CLI and the
   Flutter engine on the same inputs, compare entry content (immune to ZIP
   timestamps) — reuse the existing `diffcli`/`ZipFilesEqual` approach.

### 6.2 Test data

Generated dynamically (PNG/JPEG/WebP/BMP, multi-page CBZ, CBR from a RAR, CBZ with
ComicInfo, scrambled names, duplicates). No fixture binaries in git.

### 6.3 Coverage targets

- Core engine pipelines: mirror the reference's tested scenarios.
- VFS/workspace: ≥ 90 % of branches.
- Controllers: happy path + failure + cancellation.

---

## 7. CI/CD

- **GitHub Actions**:
  - `analyze` + `dart format --output=none --set-exit-if-changed` + `flutter test` (ubuntu).
  - `cargo test` + `cargo clippy` for the engine (ubuntu; only if Option B).
  - Build matrix: Linux, Windows, Android debug APK (and signed release on tags).
  - Samba container job for SMB integration tests.
- Cache: pub, Gradle, NDK (plus cargo if Option B).
- On tags: build and attach artifacts (AppImage/deb, installer/zip, APK/AAB).
- License check for dependencies (`flutter_oss_licenses`; `cargo-deny` if Option B).

---

## 8. Packaging and distribution

| Platform | Artifacts | Notes |
|---|---|---|
| Android | AAB (Play), universal APK, per-ABI APKs | signing via CI secrets; F-Droid recipe optional |
| Linux | AppImage, `.deb`, tarball | desktop entry + icon; libarchive system dep with graceful miss |
| Windows | Inno Setup installer, portable zip | MSVC; code signing optional |

Store metadata, icons and screenshots are produced in Phase 8. Versioning
follows the reference (`VERSION`/PKGBUILD auto-injection precedent).

---

## 9. Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Pure-Dart image pipeline too slow / quality differs | medium | high | Phase-0 benchmark; `image` tuning; optional libwebp FFI; adopt Option B (new Rust engine) |
| libarchive cannot be built/bundled for an Android ABI | medium | high | prebuilt NDK build in CI; document degradation; Option B |
| `dart_smb2` immaturity (0.1.x, small project) | medium | high | VFS abstraction; fallback smb_connect/smbj; vendor & pin libsmb2 |
| Build-time download of native libs | medium | medium | mirror/vendor binaries in our CI or releases; SHA-256 checks |
| FRB/NDK friction if Option B is chosen | low | medium | keep the `CbzEngine` facade stable; timeboxed spike |
| Android storage policies (`MANAGE_EXTERNAL_STORAGE`) | medium | medium | SAF-first; opt-in full access; SMB needs no permission |
| Image parity/perf differences vs libwebp/FPC | medium | medium | differential fixtures; WebP q75 compare; add libwebp via FFI if needed |
| Large archives × N workers exhaust Android memory | medium | high | enforce caps; bytes-only pipeline; stream writes; OOM handling |
| libarchive absent on a user's Linux | low | low | graceful degradation exactly like the reference |
| Windows path/UTF-16 issues in FFI | low | medium | dedicated Windows smoke tests in CI |

---

## 10. Open questions (need a decision before/at the phase noted)

1. **Q1 (Phase 0):** is pure Dart sufficient, or do we accept a new Rust engine
   for performance/quality? *Recommendation: pure Dart unless the benchmark fails.*
2. **Q2 (Phase 1):** Android distribution (Play vs F-Droid/sideload)? Affects
   `MANAGE_EXTERNAL_STORAGE`.
3. **Q3 (Phase 8):** ship a headless CLI in Flutter, or keep the Lazarus binary
   as the CLI and deliver a GUI-only Flutter app?
4. **Q4 (Phase 8):** Windows minimum (10) and Linux distro matrix.
5. **Q5 (Phase 1):** default UI language (`it` vs `en`).
6. **Q6 (Phase 1):** SMB profiles shared with desktop, or Android-only?

---

## 11. Immediate next actions (this branch)

1. [ ] Review this plan and resolve Q1–Q6.
2. [ ] Execute the Phase-0 engine spike and record ADR-001.
3. [ ] `flutter create` the app skeleton.
4. [ ] Stand up the Samba test container and the SMB PoC harness.
5. [ ] Build the libarchive FFI shim under `flutter/native/` and prove CBR on Android.

## 12. References

- Reference behaviour and divergences: repository `AGENTS.md`.
- Python reference: `porting/cbz_manager/` (local, git-ignored).
- Key dependencies: `dart_smb2` v0.1.3, `archive` v4.3, `image` v4.10,
  `flutter_riverpod` v3.4, `go_router` v18, plus `flutter_rust_bridge` v2.13 only
  if Option B is adopted.
