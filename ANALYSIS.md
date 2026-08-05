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

## Plan

### P0 — Lookup table in TSaveChangesThread (upageeditmodel.pas)

Replace the O(n×m) `SameText` scan with a pre-built lookup. Implemented as a sorted
lowercase-name array + binary search (`FindIdx`): build once (LowerCase + insertion
sort, O(n log n)) before the hot loop, then O(log n) per page. `TDictionary` was
considered first but FPC 3.2.2 rejects the generic in a variable declaration
(`Generics without specialization`), so the sorted-array form was used instead. The
`Consumed`/`Found` semantics of the original linear scan are preserved exactly:
an entry is only claimed by the first page that references it, and Gone pages still
mark their entry consumed.

- New import: none.
- Risk: low once the `Found`/`Consumed` pairing is preserved (a first version
  dropped it and silently lost original pages — caught by the added save-path tests).
- Tests: `TSaveChangesTest` in `tests/test_upageeditmodel.pas` covers the save path
  (renumber, delete+Gone, backup).

### P2 — Exponential growth in DoDoneStream (uzipcore.pas ~line 79)

Add a capacity field (`FEntriesCapacity`) to `TZipCollector`. On first allocation
start at 64, double on overflow. **The used count must be tracked separately
(`FEntriesCount`): after SetLength above the capacity, `Length(FEntries)` equals the
capacity, not the count — using it as the append index scatters entries (0, 64, 128…)
and leaves the array untrimmed.** The array is trimmed to the real count before
`CollectZipEntries` returns so `Length()` stays equal to the entry count.

- New import: none.
- Risk: medium — the first version kept `n := Length(FEntries)` and broke every
  `CollectZipEntries` caller (sparse entries, `Length` = capacity). Fixed by tracking
  the count and trimming; covered by `TestCollectZipEntries` and the save-path tests.
- Tests: `test_uzipeditor.pas` (entry count/names) + `TSaveChangesTest`.

### P1 — Pre-size OutEntries (upageeditmodel.pas ~lines 471, 507)

Replace `SetLength(OutEntries, Length(OutEntries) + 1)` with a counter-based approach:
pre-allocate upper bound (`High(FPages) + 1`), use `Inc(Idx)` to index, trim at the
end with `SetLength(OutEntries, Idx + 1)`.

- Risk: low. Straightforward structural change.
- Tests: same as P0 — existing tests don't cover this path.

### Execution order

P0 → P2 → P1 (each is independent; P1 refactors the same loop but doesn't depend on P0).

## Summary

Do: P0, P2, and the two `OutEntries` sites at `upageeditmodel.pas:471/507`.
Skip: `AddChange` (`main.pas:789`) and the `SortChapters` swap. The merge-site
pre-sizing (`uservicemerge.pas:811/820`) is optional cleanup.