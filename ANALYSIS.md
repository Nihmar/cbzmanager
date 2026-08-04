# Performance Analysis — Low-Hanging Optimizations

Analyzed Aug 05, 2026.

## P0 — O(n²) nested loop in `src/upageeditmodel.pas` (~line 456)

The save thread matches `FPages` entries against `AllEntries` via linear scan with
`SameText` for every page. With 100 pages that's ~10,000 calls. Build a
`TDictionary<string, Integer>` from entry names before the loop to reduce it to O(n).

**Verdict: worth doing — the biggest win.** Caveat: it runs inside the background
thread (`TSaveChangesThread`), so it never freezes the UI; it only adds latency to
saves on large archives. `src/upageeditmodel.pas:507` has a fourth `SetLength + 1`
that the original note missed.

## P1 — `SetLength(arr, Length(arr) + 1)` in 4 places

Each realloc copies the entire array and bumps the refcount of every `Name` string
already stored, so the cost of leaving it is higher than it looks. Pre-size with an
upper bound and use a counter index instead.

| Location | Array | Worth fixing? |
|----------|-------|---------------|
| `src/upageeditmodel.pas:471` | `OutEntries` | Yes — hot loop over pages |
| `src/upageeditmodel.pas:507` | `OutEntries` | Yes — same loop, metadata pass |
| `src/uservicemerge.pas:820` | `ToClean` | Marginal — small per-batch arrays |
| `src/main.pas:789` | `FChanges` | **No** — user-driven, tiny (a handful of clicks/undo) |
| `src/uservicemerge.pas:811` | `CreatedPaths` | Marginal — per-volume growth |

## P2 — `TZipCollector.DoDoneStream` in `src/uzipcore.pas:79`

Growing the entries array one element at a time for every ZIP entry. Pre-allocate
with exponential growth (start 64, double on overflow) to avoid O(n²) copies during
ZIP reads.

**Verdict: real but modest.** This runs on every CBZ open (the most frequent hot
path) and is genuinely quadratic, so it is a trivial, worthwhile fix — but the
absolute cost is small for typical 50–300 entry archives.

## P3 — Insertion sort in `src/uservicemerge.pas:248`

`SortChapters` uses insertion sort.

**Verdict: leave alone.** The comment explicitly size-delimits it ("typical chapter
counts"), it is stable and deterministic by design, and swapping it in adds churn and
regression risk for zero measured gain.

## Summary

Do: P0, P2, and the two `OutEntries` sites at `upageeditmodel.pas:471/507`.
Skip: `AddChange` (`main.pas:789`) and the `SortChapters` swap. The merge-site
pre-sizing (`uservicemerge.pas:811/820`) is optional cleanup.