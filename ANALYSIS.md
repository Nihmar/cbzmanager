# Performance Analysis — Low-Hanging Optimizations

Analyzed Aug 05, 2026.

## P0 — O(n²) nested loop in `src/upageeditmodel.pas` (~line 456)

The save thread matches `FPages` entries against `AllEntries` via linear scan with
`SameText` for every page. With 100 pages that's ~10,000 calls. Build a
`TDictionary<string, Integer>` from entry names before the loop to reduce it to O(n).

## P1 — `SetLength(arr, Length(arr) + 1)` in 4 places

Each realloc copies the entire array. Pre-size with an upper bound and use a counter
index instead.

| Location | Array |
|----------|-------|
| `src/upageeditmodel.pas:471` | `OutEntries` |
| `src/uservicemerge.pas:820` | `ToClean` |
| `src/main.pas:789` | `FChanges` |
| `src/uservicemerge.pas:811` | `CreatedPaths` |

## P2 — `TZipCollector.DoDoneStream` in `src/uzipcore.pas:79`

Growing the entries array one element at a time for every ZIP entry. Pre-allocate
with exponential growth (start 64, double on overflow) to avoid O(n²) copies during
ZIP reads.

## P3 — Insertion sort in `src/uservicemerge.pas:248`

`SortChapters` uses insertion sort. Fine for small chapter lists but
`TArray.Sort<TChapter>` would be cleaner with no downside.
