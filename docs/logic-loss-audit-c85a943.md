# Commit `c85a943` — logic-loss audit

Commit: `c85a943` ("beginning of proper ui instead of ui declaration")
Scope: refactored `TdlgMerge` from declarative (programmatic control creation
in `FormCreate`) to proper LCL form design (controls streamed from `.lfm`).

---

## 1. ❌ Series name lost (behavioral regression)

**What changed:** `EditSeries` (read-only `TEdit` showing the auto-detected
series name) was removed entirely. The dialog no longer displays it.

**Caller impact** (`main.pas` line 1237):

```pascal
// Before
Options.SeriesName := Dlg.EditSeries.Text;   // TMergeService.DetectSeriesName result

// After
Options.SeriesName := Dlg.LblFolder.Caption; // directory basename only
```

The merge operation now uses the folder basename instead of the auto-detected
series name, so volume naming will differ.

---

## 2. ❌ SpinEdit MinValue / MaxValue broken

All three `TSpinEdit` controls in `udlgmerge.lfm` have `MinValue = 9999` and
no `MaxValue`. Since controls are now streamed from the `.lfm` (not created in
code), the old runtime assignments are gone:

| Control | Old MinValue | Old MaxValue | LFM now |
|---|---|---|---|
| `EditChapterStart` | 0 | 9999 | `MinValue = 9999`, no max |
| `EditChapterEnd` | 1 | 9999 | `MinValue = 9999`, no max |
| `EditCPV` | 1 | 999 | `MinValue = 9999`, no max |

Users can only enter values ≥ 9999 — the dialog is effectively unusable.

---

## 3. ❌ "e.g. 5,6,7,3" hint label lost (UX)

`LblSeq` is declared as a private field in the class but is never created
(not in the `.lfm`, not in code). In the old declarative UI it was a visible
hint label next to the custom sequence edit, with `Enabled` toggled in
`CbManualCPVChange` / `CbCustomSeqChange`.

Now it's a dangling nil pointer and the hint is gone.

---

## 4. ⚠️ Dead private fields

`Label1`, `Label2`, `Label3` are still declared in the private section but
never created or referenced. The `.lfm` uses `LblChaptersFrom`,
`LblChaptersTo`, and `LblCPV` instead. They compile but are clutter.

---

## 5. ⚠️ `CbDelete.OnChange` wired to `CbForceChange`

In `udlgmerge.lfm`, the "Permanently delete original ch.s" checkbox has:

```
OnChange = CbForceChange
```

`CbForceChange` calls `RefreshVolumeColumn`. Harmless (no crash), but
semantically wrong — toggling the delete option should not recompute the
volume column.

---

## 6. ✅ `InitDialogChrome` removal — safe

Removed from all dialogs (`udlgmerge`, `udlgcomicinfo`, `udlgcomicinfoeditor`,
`udlgconvertresults`, `udlgrows`, `udlgseqbuilder`, `udlgvalidate`, `udlgwebp`).
The function body was already a no-op (both lines commented out), so no
behavior was lost.

---

## Summary

| # | Severity | Issue | File |
|---|----------|-------|------|
| 1 | High | Series name replaced by folder basename in merge options | `udlgmerge.pas` + `main.pas` |
| 2 | Critical | SpinEdit min/max values broken — dialog unusable | `udlgmerge.lfm` |
| 3 | Low | Hint label "e.g. 5,6,7,3" lost | `udlgmerge.pas` |
| 4 | Cosmetic | Dead private fields left behind | `udlgmerge.pas` |
| 5 | Cosmetic | Delete checkbox wired to wrong handler | `udlgmerge.lfm` |
| 6 | None | `InitDialogChrome` removal (was no-op) | 8 files |
