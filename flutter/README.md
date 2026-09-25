# CBZ Manager — Flutter port

This folder is the **ad-hoc, self-contained home of the Flutter port** of CBZ
Manager. The existing Lazarus/FPC application (repository root) is intentionally
left untouched and remains the reference implementation.

| Document | Contents |
|----------|----------|
| [`PLAN.md`](PLAN.md) | Phased, task-level roadmap, requirements, SMB feasibility, risks |
| [`TARGET.md`](TARGET.md) | Architecture decision record and target design |
| [`PARITY.md`](PARITY.md) | Lazarus unit → Flutter component mapping and parity checklist |

Tracking issue: [Nihmar/cbzmanager#7](https://github.com/Nihmar/cbzmanager/issues/7) — *Port to Flutter (Android/Linux/Windows) with SMB share support on Android*.

## Status

**Implemented** — Phases 0–8 of [`PLAN.md`](PLAN.md) are complete: the pure-Dart
engine + VFS (local, memory, SMB), the archive browser with thumbnails, deep
validation, ComicInfo editing, WebP conversion, chapter→volume merge, CBR
reading/conversion, the page editor, image search, settings, the job monitor and
the headless CLI. Linux, Windows and Android builds; `flutter test` covers the
engine, the services and the widgets.

Remaining work (app-store packaging, per-ABI bundling, backend swaps) is tracked
in [`PLAN.md`](PLAN.md) and [`TARGET.md`](TARGET.md).

## Branding

Both applications share the same artwork. The Lazarus sources stay
authoritative; the Flutter side is generated from them:

| Source (repository root) | Used for |
|--------------------------|----------|
| `pkg/cbzmanager.svg` | Android launcher icons, Linux `.desktop` icon |
| `cbzmanager.ico` | Windows `runner/resources/app_icon.ico` |

Regenerate after a logo change:

```bash
flutter/scripts/make_icons.sh   # needs rsvg-convert
```

The GTK runner looks the icon up by the `cbzmanager` theme name, which is the
name the Lazarus `Makefile`/`PKGBUILD` installs, so Linux picks up the same
artwork without extra plumbing.

## Target platforms

- **Android** (SMB shares first-class, see `PLAN.md` §2)
- **Linux** (x86_64, aarch64)
- **Windows** (x86_64)

## Ground rules

1. Do not modify or delete the Lazarus/FPC sources, `Makefile`, man page, or packaging.
2. Everything new lives under `flutter/`.
3. Archive operations stay **in RAM**; only the final output file and optional
   `_OLD` backups hit storage (local or SMB).
4. Parallel caps mirror the Pascal app: WebP/validate ≤ 8, CBR/merge/batch-edit ≤ 4.
