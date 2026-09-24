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
| 0 | Scaffolding, CI, **Rust-core-vs-pure-Dart spike**, VFS interface | Go/no-go on FRB |
| 1 | Archive browser (local + **SMB**) with thumbnails and preview | Go/no-go on Android/SMB |
| 2 | `validate` + `comicinfo` | — |
| 3 | `convert-webp` | — |
| 4 | `merge` + sequence builder | — |
| 5 | CBR preview + `cbr-to-cbz` | — |
| 6 | Page editor + batch edit | — |
| 7 | Image search ("add image from internet") | — |
| 8 | Settings, Job Monitor, i18n, packaging, CLI | Release |

**Recommended core:** the existing tested Rust crate `rust-core` (from the Tauri
port) consumed through `flutter_rust_bridge` v2 (ADR-001). A pure-Dart fallback
(`package:archive` + `package:image` + a libarchive FFI shim for CBR) is kept
viable and decided by the Phase-0 spike.

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
| Rust `smb`/`pavao` crate | 2/3 | all | Rust | viable if Rust core chosen, but less mature |

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
- **Engine** via FRB (recommended) or pure Dart; byte-oriented facade.
- **VFS** local / SAF / SMB / memory, with a localize→publish workspace.

---

## 4. Phased roadmap

Estimates are ideal engineer-days (one developer, familiar with Flutter); they
exclude review latency. Range = optimistic…pessimistic.

### Phase 0 — Foundations and spike  *(4–7 d)*

**Goal:** a building, tested shell on all three platforms and a decision on the
engine architecture.

Tasks
- [ ] `flutter create` in `flutter/app` (org `app.cbzmanager`, platforms:
      android, linux, windows). Set `minSdk 24`, `ndkVersion`, ABI filters.
- [ ] Repo hygiene: `flutter/` tracked; add `analyze`/`format` scripts; extend
      `.gitignore` for Dart/Flutter/Rust build output.
- [ ] App skeleton: `AppShell` (empty two-pane + nav scaffold), theme, routing,
      `AppLogger`, error boundary.
- [ ] Define `Engine` facade (`TARGET.md` §4) and `Vfs` interface (`§5`) with a
      `MemoryVfs` implementation for tests.
- [ ] **Engine spike:** add FRB, expose one rust-core function (in-memory
      validate), call it from Dart; build and run on Linux and an Android
      emulator. Measure build time, APK size, cold-call latency.
- [ ] Alternative spike (timeboxed, only if FRB stalls): `archive` + `image`
      ZIP/convert round-trip for a CBZ to prove Option A.
- [ ] CI skeleton: GitHub Actions matrix (ubuntu, windows, macos-for-ios-later)
      running `flutter analyze`, `flutter test`, `cargo test`; Android debug APK
      build job.
- [ ] Decide ADR-001 → update `TARGET.md` decision log.

**Definition of done**
- `flutter run -d linux` and `flutter run` on an Android emulator both launch the
  empty shell.
- `flutter test` and the Rust tests pass in CI.
- Engine decision recorded; the facade is implemented by at least one backend.

**Risks:** FRB/NDK toolchain friction → mitigate with the pure-Dart fallback.

---

### Phase 1 — VFS, SMB PoC and archive browser  *(8–14 d)*

**Goal:** browse a folder (local and SMB), show first-page thumbnails, open a page
preview. This phase proves requirement 2 end-to-end.

Tasks
- [ ] `LocalVfs` (desktop + Android app-scoped dirs), tree-URI/SAF access for
      user-chosen Android folders, `MemoryVfs` for tests.
- [ ] `SmbVfs` on `dart_smb2`: connect, list shares/dirs, stat, read/write,
      rename/delete; connection profile model + secure storage.
- [ ] `Workspace`: localisation cache, atomic publish (`.new`→rename), `_OLD.cbz`
      backup, orphan-cache cleanup on start.
- [ ] Thumbnail loader: worker pool (≤ 4), I/O on a background isolate/async,
      LRU cache at 320×400, incremental publication to the grid (port of
      `TLoadThread`/`TThumbThread` batch+sort semantics).
- [ ] Browser UI: file grid/list with thumbnails, sort by byte-wise name
      (case-insensitive extension match), multi-select + context menu, folder
      picker (local + SMB), drag-and-drop on desktop.
- [ ] Page preview: single-archive loader, page carousel/grid, zoom/pan
      (`InteractiveViewer`), read-only badge for CBR.
- [ ] **SMB PoC gate** against a Samba container: list → download → convert →
      upload → verify (uses the Phase-0 engine once available; a no-op engine is
      acceptable for the connectivity half).
- [ ] Widget tests for the browser + preview; unit tests for `MemoryVfs`,
      workspace publish/backup, and sort order.

**Definition of done**
- On Android (device/emulator) a user can add an SMB share, browse it, open a CBZ,
  page through thumbnails and preview a page.
- On Linux and Windows the same flow works against a local folder and a mounted
  SMB path (SmbVfs optional).
- Thumbnails are generated off the UI thread; cancelling/changing folder leaves
  no leaked workers or stale items.

**Gate:** if SMB PoC fails → fallback chain → possibly drop Android.

---

### Phase 2 — Validate + ComicInfo  *(5–8 d)*

- [ ] Engine: `validate` (deep, per-image checks, parallel) and ComicInfo
      scan/strip; wire to rust-core (or pure Dart).
- [ ] `validate` feature: folder scope, options (threads), results dialog
      (per-file/per-image errors), export of the report (copy/save).
- [ ] `comicinfo` feature: scan report, remove with optional backup, and the
      ComicInfo **viewer/editor** (parse/generate XML).
- [ ] Progress + cancellation through the Job model.
- [ ] Rust/Dart tests + widget tests; parallel determinism (threads 1 vs 4).

**DoD:** parity with the reference for validate/comicinfo, including file-level
error surfacing and the threads cap.

---

### Phase 3 — Convert to WebP  *(5–8 d)*

- [ ] Engine `convertWebp`: q75, only-if-smaller, filter ComicInfo, renumber
      `page_NNNN.*`, parallel decode+encode, deterministic output.
- [ ] Feature UI: folder scope, delete-or-backup, threads spin, results summary.
- [ ] Workspace integration: backup/delete/publish over VFS (local + SMB).
- [ ] Tests: encode round-trips, only-if-smaller, determinism, backup rules.

**DoD:** a folder batch conversion produces archives byte-identical to the
reference for identical inputs (excluding timestamps).

---

### Phase 4 — Merge + sequence builder  *(8–12 d)*

- [ ] Engine `merge`: classification, CPV arithmetic (real division, Python-exact),
      numbering continuation, force, chapters list, chapters-per-volume,
      rollback, parallel volume build, optional per-volume ComicInfo.
- [ ] Merge dialog: source range, CPV manual/auto, force, custom sequence,
      delete/backup, threads, live volume preview column.
- [ ] Sequence builder: zoomable thumbnail grid, multi-select, N-chapter volumes,
      add/undo, preview of resulting volumes.
- [ ] Multi-series handling (one dialog run per series, like the reference).
- [ ] Tests: CPV edge cases, force, overflow skipping, resume after existing
      volumes, parallel determinism.

**DoD:** parity with the documented merge divergences (see the reference
AGENTS notes) and a working sequence builder.

---

### Phase 5 — CBR and `cbr-to-cbz`  *(6–10 d)*

- [ ] Engine CBR: read via libarchive (dynamic load + graceful degradation),
      list/read entries; ensure the native lib is bundled on Android and found on
      desktop.
- [ ] CBR preview (read-only) feeding the browser/preview from Phase 1.
- [ ] `cbr-to-cbz` feature: folder scope, skip-existing, delete-source, threads,
      results summary; exit/status semantics when libarchive is missing.
- [ ] Tests: zip-format `.cbr` fixtures, a guarded real-RAR test, parallel
      determinism (threads 1 vs 4), delete-source and skip-existing.

**DoD:** CBR archives preview and convert; missing libarchive degrades exactly
like the reference.

---

### Phase 6 — Page model, page editor, batch edit  *(10–16 d)*

- [ ] Dart page model mirroring `TPageState`/`TChange`/`TPageEditModel`
      (delete/move/insert, renumber, edited bytes precedence, baseline/revert,
      undo log).
- [ ] Page editor dialog: resize (aspect lock, box filter), colour pipeline
      (sliders + live preview + grayscale/sepia/invert), split (draggable cut
      lines → N+1 pieces), encode in the original format (GIF/TIFF→PNG).
- [ ] Save thread: staged changes committed on "Save changes"; backup/rename.
- [ ] Batch edit: selection → uniform resize/colour/split, preview of the first
      page, header "N pages → M pieces", staged results.
- [ ] Reorder/delete/insert via drag and drop; renumber preview.
- [ ] Tests: pure image-edit ops (resample/colour/split/encode round-trips),
      model semantics, staging, split count, determinism.

**DoD:** the single-file editor supersedes the reference's delete/renumber use
case; batch edit matches the reference pipeline.

---

### Phase 7 — Image search / add image from internet  *(4–7 d)*

- [ ] Engine/client `imageSearch`: MangaDex (default) and the other providers
      from `uimgsrc.pas`, plus pasted URL; HTTPS with certificate validation.
- [ ] UI: provider combo, query, results list with thumbnails and license/source
      line, download progress, "Add as first page" (staged in the page model).
- [ ] Offline-testable JSON parsers (mirror `test_uimgsrc`).
- [ ] Rate-limit/error UX (e.g. anonymous Openverse limits).

**DoD:** parity with the reference "add image from internet" flow.

---

### Phase 8 — Settings, Job Monitor, i18n, packaging, CLI, release  *(8–14 d)*

- [ ] Settings store (versioned) + settings UI; thread-count persistence per
      operation; theme; language.
- [ ] Job Monitor: desktop floating window (`window_manager`) / mobile bottom
      sheet; progress, task label, elapsed time, scrolling log; cancel.
- [ ] i18n (`it`, `en`) via ARB; accessibility pass; keyboard shortcuts on desktop.
- [ ] Packaging:
      - Android: signed AAB + universal APK; ABI splits; F-Droid metadata if desired.
      - Linux: AppImage + `.deb` (+ `.rpm` optional), desktop entry, icon.
      - Windows: installer (Inno/WiX) + portable zip.
- [ ] (Optional) headless CLI entrypoint (`flutter/` Dart CLI or reuse the
      Lazarus binary) with the reference exit codes 0/1/2.
- [ ] Docs: README, screenshots, parity statement, known limitations.
- [ ] Release checklist and a first tagged build.

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
2. **Rust core** (Rust): reuse and extend `rust-core/tests`; determinism per
   thread count; fixtures generated at test time (no binaries committed).
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
  - `cargo test` + `cargo clippy` for the core (ubuntu).
  - Build matrix: Linux, Windows, Android debug APK (and signed release on tags).
  - Samba container job for SMB integration tests.
- Cache: pub, cargo, Gradle, NDK.
- On tags: build and attach artifacts (AppImage/deb, installer/zip, APK/AAB).
- License check for dependencies (`flutter_oss_licenses` or `cargo-deny`).

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
| FRB/NDK integration friction | medium | high | Phase-0 timeboxed spike; pure-Dart fallback; keep facade stable |
| `dart_smb2` immaturity (0.1.x, small project) | medium | high | VFS abstraction; fallback smb_connect/smbj; vendor & pin libsmb2 |
| Build-time download of native libs | medium | medium | mirror/vendor binaries in our CI or releases; SHA-256 checks |
| Rust core lives on an unmerged branch | high | medium | vendor into `flutter/rust/`; plan shared `core/` extraction |
| Android storage policies (`MANAGE_EXTERNAL_STORAGE`) | medium | medium | SAF-first; opt-in full access; SMB needs no permission |
| Image parity/perf differences vs libwebp/FPC | medium | medium | differential fixtures; WebP q75 compare; add libwebp via FFI if needed |
| Large archives × N workers exhaust Android memory | medium | high | enforce caps; bytes-only pipeline; stream writes; OOM handling |
| libarchive absent on a user's Linux | low | low | graceful degradation exactly like the reference |
| Windows path/UTF-16 issues in FFI | low | medium | dedicated Windows smoke tests in CI |
| Tauri/Flutter core divergence | medium | medium | single shared `rust-core` as the source of truth |

---

## 10. Open questions (need a decision before/at the phase noted)

1. **Q1 (Phase 0):** shared top-level `core/` for Tauri+Flutter, or per-port
   vendoring? *Recommendation: vendor now, extract later.*
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
5. [ ] Vendor `rust-core` under `flutter/rust/` (if Option B confirmed).

## 12. References

- Reference behaviour and divergences: repository `AGENTS.md`.
- Python reference: `porting/cbz_manager/` (local, git-ignored).
- Tauri port and its Rust core: branch `origin/porting/tauri`
  (`rust-core/`, `PLAN.md`, `TARGET.md`, `GAPS.md`).
- Key dependencies: `flutter_rust_bridge` v2.13, `dart_smb2` v0.1.3,
  `archive` v4.3, `image` v4.10, `flutter_riverpod` v3.4, `go_router` v18.
