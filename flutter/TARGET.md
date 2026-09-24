# Flutter port — Target architecture (ADR)

Status: **proposed** (review before Phase 0 ends).
This document records the *why* behind the architecture; `PLAN.md` records the
*when* and the task breakdown.

---

## 1. Context and forces

CBZ Manager is a comic-archive manager. The reference (Lazarus/FPC) application
is a two-pane GUI (file list with thumbnails + page preview/editor) plus a
headless CLI. Its core is a set of **in-RAM** pipelines:

- ZIP read/write (`TZipEntries`, `CollectZipEntries`, `WriteZipFromEntries`).
- Image decode/scale/encode (JPEG q92, PNG, BMP, WebP q75; GIF/TIFF → PNG).
- CBR/RAR read through **libarchive** (dynamic loading, graceful degradation).
- Operations: `validate`, `convert-webp`, `merge`, `remove-comicinfo`,
  `cbr-to-cbz`, in-place page editor, batch page-edit.
- Parallel worker pools with fixed caps (8 for WebP/validate, 4 for
  CBR/merge/batch-edit).

A second, already-written port exists: the **Tauri** port
(`origin/porting/tauri`) with a tested Rust crate, `rust-core`, implementing
ZIP ops, image edit, validate, merge, comicinfo, CBR reading, batch edit and the
page model. That crate is the most valuable existing asset for this port.

Forces driving the design:

- **Cross-platform**, including a real Android build (NDK, ABI splits, storage).
- **CBR/RAR support is mandatory** for parity — and there is no usable pure-Dart
  RAR decoder (`package:archive` ships only zip/gzip/bzip2). Native code is
  required regardless of the chosen core language.
- **SMB on Android** is a first-class requirement (see `PLAN.md` §2).
- The team wants to "try Flutter": the UI/UX layer should be idiomatic Flutter,
  and the core should be as cheap to reach parity as possible.

---

## 2. Layered architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│ Flutter UI (Material 3)                                              │
│  screens/  widgets/  dialogs/  router/  theme/                       │
└───────────────▲──────────────────────────────┬───────────────────────┘
                │ Riverpod providers            │ intents
┌───────────────┴──────────────────────────────▼───────────────────────┐
│ Feature controllers (application layer)                              │
│  browser · validate · convertWebp · merge · cbr · comicinfo           │
│  pageEditor · batchEdit · imageSearch · jobMonitor · settings         │
│  ↳ orchestration, job graph, progress fan-out, cancellation           │
└───────────────▲──────────────────────────────┬───────────────────────┘
                │ result/progress streams       │ engine calls
┌───────────────┴──────────────────────────────▼───────────────────────┐
│ Engine layer (native pipeline)                                       │
│  A) Rust `cbz-core` via flutter_rust_bridge   ← recommended          │
│  B) pure-Dart core (`archive` + `image` + libarchive FFI shim)        │
│  Both expose the same async facade: validate/convert/merge/cbr/...    │
└───────────────▲──────────────────────────────┬───────────────────────┘
                │ bytes                          │ bytes
┌───────────────┴──────────────────────────────▼───────────────────────┐
│ VFS / Workspace layer                                                │
│  LocalVfs · TreeUriVfs (SAF) · SmbVfs (libsmb2) · MemoryVfs (tests)   │
│  ↳ list / stat / readAll / writeAll / rename / delete / localize      │
└──────────────────────────────────────────────────────────────────────┘
```

Key invariant: **the engine only ever sees `Uint8List` / byte streams**, never
paths. That is what makes SMB and SAF transparent to every operation and keeps
the port faithful to the in-RAM rule.

---

## 3. ADR-001 — Core engine: Rust `rust-core` vs pure Dart

### Decision

**Recommended: Option B — Rust core exposed through `flutter_rust_bridge` (FRB v2).**
Everything in the engine diagram above, all UI/orchestration/VFS in Dart.

**Fallback / hybrid (Option A):** pure-Dart core for ZIP/image operations
(`package:archive` + `package:image`) with a small `dart:ffi` shim to libarchive
for CBR only. Adopt this only if the Phase-0 FRB/NDK spike fails its timebox.

### Rationale

| Criterion | Option A — pure Dart | Option B — Rust core (FRB) |
|---|---|---|
| ZIP read/write | `archive` — good | `zip` crate — proven (Tauri) |
| JPEG/PNG/BMP decode+encode | `image` — good, slower | `image` crate — fast |
| WebP encode | `image` `WebPEncoder` — pure Dart, slow | libwebp — fast, q75 parity |
| **RAR/CBR** | **no pure-Dart decoder** → still needs libarchive FFI | libarchive via `libloading` — already done |
| Parallelism | isolates (data copies) | `rayon` — already done |
| Parity with reference | re-implement everything | `rust-core` is already tested |
| Reuse across Tauri + Flutter | none | same crate, one source of truth |
| Build complexity | `flutter build` + C shim for libarchive per ABI | + Rust toolchain, `cargo-ndk`, FRB codegen |
| Binary size | smaller | larger (Rust runtime + codecs) |
| Risk | CBR/WebP quality and speed | FRB/NDK setup, cross-branch vendoring |

Because CBR forces native code onto Android either way, Option B *concentrates*
the existing native work instead of adding a second native stack. The Tauri
crate already encodes the exact reference semantics (merge CPV arithmetic,
convert "only if smaller", rollback rules, parallel determinism), which removes
the largest source of porting bugs.

### Consequences

- The Rust crate becomes a **shared engine** consumed by both Tauri and Flutter.
  For this branch it is **vendored** under `flutter/rust/` (copied from
  `origin/porting/tauri`) so the Flutter build is self-contained. Extracting it
  to a top-level `core/` is a follow-up (see `PLAN.md` Phase 8) and must not
  block this port.
- FRB codegen output is committed (or regenerated in CI) so builds are
  reproducible without the codegen tool locally.
- If Option A is chosen after the spike, this ADR is superseded; keep the VFS
  and controller layers unchanged — only the `Engine` facade implementation
  changes.

### Phase-0 spike (timebox: 2 days)

1. `flutter create` desktop + Android app in `flutter/app/`.
2. Add `rust_builder`/FRB, expose **one** existing rust-core function
   (`validate` over an in-memory `Vec<u8>`) and call it from Dart.
3. Build & run on **Linux** and on an **Android emulator** (arm64 or x86_64).
4. Measure: build time, APK size delta, cold-call latency.
5. Go/no-go on Option B; otherwise switch to Option A.

---

## 4. ADR-002 — Engine facade (Dart API)

Regardless of A/B, Dart sees one abstract surface. No Flutter types leak into it.

```dart
abstract class CbzEngine {
  Future<ValidateResult> validate(ArchiveData data, {int threads = 0});
  Future<ConvertResult> convertWebp(ArchiveData data, ConvertOptions o);
  Future<MergeResult> merge(List<ArchiveData> chapters, MergeOptions o);
  Future<ConvertResult> cbrToCbz(ArchiveData cbr, {bool deleteSource = false});
  Future<ScanResult> scanComicInfo(ArchiveData data);
  Future<ArchiveData> stripComicInfo(ArchiveData data);
  Future<ArchiveData> applyPageEdits(ArchiveData data, List<PageEdit> edits);
  Future<ArchiveData> applyBatchEdit(ArchiveData data, BatchEditOptions o);
  Stream<JobProgress> progress(JobHandle job);
}
```

- `ArchiveData` = `{ Uint8List bytes, String name }` (engine-side, FRB-translated).
- Long jobs return a `JobHandle` (id) plus a `Stream<JobProgress>` so the UI can
  show the Job Monitor; cancellation is `handle.cancel()`.
- Results carry `success`, counters, per-item errors and the produced bytes, never
  exceptions across the FFI boundary (mirror `TMergeResult` etc.).

---

## 5. ADR-003 — VFS / Workspace abstraction

All filesystem access goes through one interface so local, SAF and SMB are
interchangeable:

```dart
abstract class Vfs {
  String get scheme;                       // file, content, smb
  Future<List<VfsEntry>> list(String dir);  // non-recursive, sorted compareStr
  Future<VfsStat> stat(String path);
  Future<bool> exists(String path);
  Future<Uint8List> readAll(String path);
  Stream<List<int>> openRead(String path, {int? start, int? end});
  Future<void> writeAll(String path, List<int> bytes);
  StreamSink<List<int>> openWrite(String path); // for large outputs
  Future<void> rename(String from, String to);
  Future<void> delete(String path);
  Future<void> mkdir(String path);
}
```

- `VfsEntry`: name, isDirectory, size, modified; `ArchiveKind` derived from
  extension (CBZ/CBR) case-insensitively.
- Sorting uses byte-wise `compareTo` on UTF-8 code units to match the reference
  (`CompareStr` / Python `sorted`) — **not** locale collation.

### Workspace model (the SMB answer)

`Workspace` materialises one archive for processing:

1. `localize(src)`: if `src` is a local file → use it directly; if remote
   (SMB/SAF) → download into `getTemporaryDirectory()/cbzmanager/<jobId>/` and
   return the local path.
2. Run the in-RAM engine on the bytes.
3. `publish(dst, bytes)`: write atomically (`foo.new` → rename) on the target
   VFS; create/delete `_OLD.cbz` backups through the VFS.
4. Delete the localisation cache on job completion (and on startup for orphans).

Because the engine is byte-oriented and operations consume whole archives, this
"download → process → upload" model is sufficient and far simpler than a
random-access SMB VFS. It also works for SAF content URIs unchanged.

---

## 6. ADR-004 — SMB implementation

**Chosen:** `dart_smb2` (SMB2/3 on libsmb2 v6.1.0, BSD-3) behind `SmbVfs`.

- Prebuilt native libs: Android (arm64-v8a, armeabi-v7a, x86_64, API 24+),
  Linux (x86_64, aarch64), Windows (x86_64, arm64). Downloaded from GitHub
  Releases at build time with SHA-256 verification.
- Supports list/stat/read (full, range, streamed)/write (full, chunked)/rename/
  delete/mkdir + a reconnect-capable worker pool — exactly the `Vfs` surface.

Fallbacks, in order:

1. **Vendor/sha-pin `libsmb2` binaries** in our own release/asset store or CI
   cache if the upstream download is ever unavailable (supply-chain hygiene).
2. `smb_connect` (pure Dart, SMB ≤ 2.1) as a stopgap.
3. Android platform channel with `smbj` (Java SMB2/3) — most robust but most code.
4. If all fail: ship Linux + Windows, drop Android (per issue #7).

Credentials: `flutter_secure_storage` (Android Keystore / DPAPI / libsecret).
Never persist passwords in `shared_preferences`.

### Desktop networking note

On Linux/Windows the OS may already expose SMB as a mounted path (`file://`).
`SmbVfs` is still offered so users can browse without mounting, but a mounted
share is handled by `LocalVfs` with zero extra code.

---

## 7. ADR-005 — Concurrency & progress

- **Option B:** all engine calls are `async`; FRB runs them on a Rust worker
  thread/`rayon` pool. Progress is pushed through an FRB `StreamSink` mapped to
  a Dart `Stream<JobProgress>`.
- **Option A:** a Dart worker pool (`package:pool` or a small isolate manager)
  runs CPU-bound pipelines in isolates; `Uint8List` results are passed with
  `TransferableTypedData` where possible.
- One **Job** = one user-visible task (validate a folder, convert a file, merge a
  series, edit a page). `JobController` owns: id, label, `ValueNotifier<double>
  percent`, log sink, cancel token, state (`queued/running/done/failed/cancelled`).
- A single global `JobRegistry` feeds the Job Monitor window (desktop) / bottom
  sheet (mobile).
- Caps: `min(onlineCpus, cap)` with cap 8 (WebP/validate) and 4
  (CBR/merge/batch-edit); `0` means auto. User override in settings (spin edit),
  mirroring the reference dialogs.

---

## 8. ADR-006 — State management, navigation, UI

- **Riverpod v3** (`flutter_riverpod`): providers per feature; controllers are
  `AsyncNotifier`s exposing job state. Chosen over `provider`/BLoC for testability
  and because the Tauri frontend already used a store model.
- **Navigation:** `go_router`. Mobile uses a nav bar / bottom sheet for jobs and
  dialogs; desktop keeps the two-pane layout plus a native menu bar and a
  floating Job Monitor (via `window_manager`).
- **Adaptive shell:** one `AppShell` with two layouts:
  - desktop/wide: two panes (browser | preview) + menu bar + status bar.
  - mobile/narrow: file grid → tap → full-screen page carousel; operations from
    an overflow menu / FAB; job progress in a persistent bottom bar.
- **Preview/zoom:** `InteractiveViewer` + `PhotoView`-style gestures; centre-
  anchored Ctrl+wheel zoom replicated via a `TransformationController` (port of
  `CenterAnchorScrollPos`).
- **Editor:** custom `CustomPaint` overlays for split cut lines and colour sliders
  with a debounced live preview (decoded at reduced resolution).

---

## 9. Project layout

```
flutter/
  README.md  PLAN.md  TARGET.md  PARITY.md
  app/                          # flutter create . (org: app.cbzmanager)
    lib/
      main.dart
      src/
        app/            # shell, router, theme
        engine/         # Engine facade + FRB bindings (generated) + models
        vfs/            # Vfs interface + local/saf/smb/memory + workspace
        jobs/           # JobController, JobRegistry, progress models
        features/
          browser/      # file list, thumbnails, preview
          validate/
          convert_webp/
          merge/        # incl. sequence builder
          cbr/
          comicinfo/
          page_editor/
          batch_edit/
          image_search/
          settings/
        l10n/           # it/en ARB
    android/  linux/  windows/
    test/  integration_test/  assets/
  rust/                 # vendored rust-core + FRB crate (Option B) / FFI shim (A)
  scripts/              # codegen, libarchive build, packaging helpers
  fixtures/             # generated test archives (no binaries committed)
```

`flutter/` is tracked (unlike `porting/`, which is git-ignored). The Lazarus
tree is untouched.

---

## 10. Native dependencies

| Library | Used for | Desktop | Android | Notes |
|---|---|---|---|---|
| libarchive | CBR/RAR read | system `.so`/`.dll` via dynamic load; graceful miss | cross-compiled per ABI, bundled | same dynamic-load + degradation strategy as `uarchive.pas` |
| libwebp | WebP encode (Option A only) | system / `image` fallback | bundled | not needed with Option B (Rust `webp` crate) |
| libsmb2 | SMB2/3 | via `dart_smb2` prebuilt | via `dart_smb2` prebuilt | vendor/sha-pin in CI |

Support libraries (Option A): libjpeg-turbo / libpng are **not** required — the
`image` package is pure Dart; only libarchive (CBR) and libsmb2 are native.

---

## 11. Platform specifics

### Android
- `minSdk 24` (dart_smb2 floor), `targetSdk` current, `ndkVersion` matching the
  installed NDK; `abiFilters` `arm64-v8a`, `armeabi-v7a`, `x86_64` (+ App Bundle
  splits).
- Local libraries: prefer **SAF persisted tree URI** (`file_selector` /
  `tree_uri` access) for user-chosen folders. Offer `MANAGE_EXTERNAL_STORAGE`
  only as an opt-in "full file access" mode (Play policy sensitive); SMB needs no
  storage permission.
- `INTERNET` permission; `usesCleartextTraffic=false` (SMB, not HTTP).
- Background work: jobs run in the app process; use a foreground service only if
  long merges must survive backgrounding (Phase 8, optional).
- File provider + `open_filex` to open a produced CBZ in an external reader
  (nice-to-have).

### Linux
- `flutter build linux`; package AppImage + `.deb` (and `.rpm` optional); desktop
  entry + icon; `libsecret` for credential storage; `window_manager` for the
  floating monitor and remember-window-size.
- Ship libarchive as a system dependency with graceful degradation, as Pascal does.
- Optional Flatpak later (filesystem/SMB portals).

### Windows
- `flutter build windows`; MSVC toolchain; WiX/Inno installer or portable zip;
  DPAPI via `flutter_secure_storage`; long-path support; UTF-16 path handling in
  any FFI shim.

---

## 12. Error, result and logging model

- Engine errors are values (`Result`-like), never thrown across FFI; each result
  carries `errorMessage` and per-item errors, matching `TMergeResult`,
  `TDeletePagesResult`, `TConvertResult`, etc.
- `AppLogger` (Dart) mirrors `ulog.pas`: timestamped, level-filtered, thread-safe
  (single isolate sink), surfaced in the Job Monitor log pane and to a rotating
  file on desktop.
- User-facing errors are short and actionable ("Unable to create file …"), with
  a "details" expander for the technical message.

---

## 13. Settings and secrets

- `shared_preferences` (JSON blob) for UI settings, mirroring the INI keys:
  window geometry, zoom, last directory, per-operation options, thread counts,
  theme, language.
- `flutter_secure_storage` for SMB credentials/tokens only.
- Settings are versioned; a migration function handles schema changes.

---

## 14. Non-functional targets

- **Memory:** never hold more than `threads × (one decoded page)` beyond the
  input archives, matching the reference caps. Enforce caps when the user picks a
  thread count (clamp + explain).
- **Determinism:** output must be byte-identical for any thread count (the
  reference guarantees this; tests assert it).
- **i18n:** `flutter_localizations` + ARB, `it` and `en` first.
- **Accessibility:** semantic labels on all icon actions; keyboard shortcuts on
  desktop; focus order.
- **Offline:** all operations except image search work offline.

---

## 15. Testing strategy (summary — detail in `PLAN.md` §9)

- Dart unit tests (VFS, workspace, controllers, sort order, result mapping).
- Rust core tests: reuse `rust-core/tests` (already comprehensive).
- Golden/widget tests for the browser, preview, editor and dialogs.
- **SMB integration** against a Samba container (`dperson/samba` or
  `dockurr/samba`) exercising list/read/write/rename/delete and a full
  convert/merge round-trip.
- Cross-platform CI: Linux + Windows + Android build; emulator smoke test.
- Differential parity tests: run the same fixtures through the Lazarus CLI and the
  Flutter engine, compare archives (entry content, not timestamps).

---

## 16. Decision log

| # | Decision | Status |
|---|---|---|
| 001 | Rust core via FRB; pure-Dart fallback | proposed, Phase-0 gate |
| 002 | Byte-oriented abstract `CbzEngine` facade | proposed |
| 003 | `Vfs` + `Workspace` (localize/publish) | proposed |
| 004 | SMB via `dart_smb2`/libsmb2; SAF/MANAGE for local | proposed, Phase-1 gate |
| 005 | Job model + streaming progress; caps 8/4 | proposed |
| 006 | Riverpod + go_router + adaptive shell | proposed |
| 007 | `flutter/` tracked; Lazarus untouched | accepted |

## 17. Open questions

1. Is a shared top-level `core/` (Rust) wanted, or keep per-port vendoring?
2. Play Store distribution for Android, or sideload/F-Droid only? (affects
   `MANAGE_EXTERNAL_STORAGE` and dependency licensing review.)
3. Is a full headless CLI part of the Flutter deliverable, or keep the Lazarus
   binary as the CLI and ship Flutter GUI-only?
4. Minimum Windows version (10?) and Linux distro matrix for packaging.
5. Language default: Italian-first (reference UI is Italian-ish) or English-first?
