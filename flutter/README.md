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

**Planning.** No application code exists yet. This folder currently contains only
the plan. Implementation starts with Phase 0 (see `PLAN.md`).

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
