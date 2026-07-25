# Plan: Replicate mockup UI in Lazarus GUI

Based on `docs/mockup.html`. The current codebase has a skeleton with
browse + preview + zoom. The plan below closes the gap to the mockup.

---

## 1. Window structure (main.lfm / main.pas)

| Current | Target (mockup) |
|---------|-----------------|
| `PanelTop` (TEdit + BtnBrowse) | Keep native system title bar — no custom title bar |
| (missing) | **Menu bar** (28px): File, Archivio, Pagine, Visualizza — `TMainMenu` attached to the form |
| (missing) | **Toolbar** (42px): Sfoglia, Valida, Converti WebP, Unisci, Trova simili, Anteprima toggle — `TToolBar` with `TToolButton`s, separators, SVG-like icons (use `TImageList`) |
| `PanelTop` currently has path + browse | Repurpose as **path row** (38px): keep `EditDir` (read-only, mono font) + `BtnBrowse`("Sfoglia...") |
| `PanelMiddle` with `LVFiles` | **Client area**: file list pane (left) + optional preview pane (right) + `TSplitter` (already present) |
| (missing) | **Status bar** (28px): message text, progress bar, zoom slider — replace `PanelBottom` with a `TStatusBar` or rework into a `TPanel` that mimics it |
| (missing) | **Stage bar** inside preview: a colored bar (warning background) showing pending changes + "Annulla" / "Salva modifiche" buttons |

### Specific changes

- Replace `PanelBottom` with a mimic of the mockup's `statusbar` (message | progress bar | zoom trackbar + zoom value label).
- Add `TMainMenu` with top-level items: File, Archivio, Pagine, Visualizza. Populate sub-items from the mockup's `#mFile`, `#mArch`, `#mPag`, `#mVis`.
- Add `TToolBar` at top with `TToolButton`s for each `[data-act]` in the mockup's `.toolbar`.
- Keep `SplitterPreview` but ensure it is hidden until a file is opened.
- In the preview pane (`PanelSingleFile`), add:
  - **Preview header** (30px): `LblPreviewFile` + page count label + close button (icon)
  - **Page tools bar** (flex): Delete, Delete Rows..., separator, Move up/down, Move to start/end, separator, Sort by name, Reverse
  - **Stage bar** (hidden unless changes pending): dot indicator, message label, "Annulla" btn, "Salva modifiche" btn
  - `LVPages` remains as the thumbnail grid

---

## 2. File list view

The mockup shows a wrap-around thumbnail grid with:
- `.lvitem` (selected has blue bg, current has dotted outline)
- Thumbnail with optional badge (green "OK" or red "ZIP")
- Caption below

**Changes to `LVFiles`:**
- Currently `vsIcon` with `AutoArrange` — this is already close.
- Add per-item badge overlay via `TListItem.StateIndex` or owner-draw (custom `OnDrawItem` / `OnAdvancedCustomDrawItem`).
- Ensure multi-select works with Ctrl/Shift.
- Right-click shows `PMFiles` context menu (currently only "Apri file"; add all items from mockup's `#ctxFile`).
- Double-click opens preview (already working).

---

## 3. Preview pane (pages view)

**Changes to `LVPages`:**
- Display all pages of the opened CBZ as a thumbnail grid (already working via `TPagesThread`).
- Selected page has a highlight ring; current (focused) has a dotted ring.
- Deleted pages shown with `opacity: 0.32` and an X diagonal — implement via owner-draw or `LVPages.OnAdvancedCustomDrawItem`.
- Drag-and-drop reorder: implement `LVPages.OnDragOver` / `OnDragDrop` to move pages.
- Single-click selects (Ctrl/Shift for range).
- Right-click shows page context menu (mockup's `#ctxPage`).

---

## 4. Stage bar (pending changes)

Add a `TPanel` inside `PanelSingleFile` above `LVPages`:
- `Visible := False` initially.
- Contains: a colored dot (TShape), a message label, "Annulla" button, "Salva modifiche" button.
- Shown when `FChanges.Count > 0` after any delete/move/reorder.
- "Salva modifiche" writes changes to disk (rewrite CBZ).
- "Annulla" discards in-memory changes and reloads from `FBaseline`.

---

## 5. Toolbar actions (operations)

Each toolbar button should open a dialog. All dialogs must be modal.

### 5.1 Validate (`dlgValidate`)
- Iterate selected (or all) CBZ files.
- Check valid ZIP + all images readable (reuse `IsValidCBZ` + `ForEachImage`).
- Show result table: file name, pass/fail badge, image count, notes.

### 5.2 Convert to WebP (`dlgWebp`)
- Modal dialog with:
  - Quality slider (30–100, default 75)
  - Checkboxes: replace only if smaller, skip existing WebP
  - "Remove ComicInfo.xml" checkbox
  - "Rename to page_NNNN" checkbox
  - Backup (`_OLD.cbz`) vs delete radio
- Call Python-equivalent logic from `porting/cbz_manager/src/cbz_manager/convert.py`.

### 5.3 Merge chapters (`dlgMerge`)
- Parse chapter files matching `Title - NNNN.cbz`.
- Dialog shows series name, chapter count.
- Chapters-per-volume: auto-calculate or manual.
- Chapter range filter.
- Table of resulting volumes.
- "Sovrascrivi esistenti" checkbox (--force).

### 5.4 Delete pages / Delete rows (`dlgRows`)
- Modal dialog with:
  - Text input for ranges: `1, 4, 7-10, 15`
  - Live preview strip showing mini-thumbnails with hit highlighting
  - Renumber checkbox
  - Remove ComicInfo.xml checkbox
- On confirm, mark pages as `gone` in the page list and show stage bar.

### 5.5 Find similar pages (`dlgSimilar`)
- Modal dialog (wide) with:
  - Hamming distance threshold slider (0–16, default 10 or 5)
  - Scope: selected files or all files
  - Results grouped by similarity group
  - Each group: expandable, shows duplicate pages, checkboxes to keep/delete
  - Actions: "Estrai in cartella..." (extract), "Elimina duplicati"
- Similarity engine: difference hash (64-bit). Use the Python reference in `porting/cbz_manager/src/cbz_manager/find_similar.py`.

### 5.6 Delete by ID (`dlgById`)
- Modal dialog with:
  - Multiline text area for `filename.cbz:entry.ext` IDs (one per line)
  - "Carica da CSV..." button (file open dialog)
  - Live count of valid IDs
  - Renumber checkbox
- On confirm, process across multiple CBZ files.

### 5.7 Remove ComicInfo.xml (`dlgComicInfo`)
- Shows table of selected files with ComicInfo.xml status.
- Backup checkbox.
- Rewrites each CBZ without the XML entry.

---

## 6. Context menus

### 6.1 File context menu (`PMFiles`, already exists)
Add all items from mockup's `#ctxFile`:
- Apri file (already exists)
- Rimuovi ComicInfo.xml
- Elimina righe...
- Riordina pagine...
- (separator)
- Valida
- Converti in WebP...
- Unisci in volumi...
- Trova pagine simili...

### 6.2 Page context menu (new `PMPages`)
Add all items from mockup's `#ctxPage`:
- Elimina pagina / Elimina N pagine
- Elimina righe...
- (separator)
- Sposta su, Sposta giù, Sposta a inizio, Sposta a fine

---

## 7. Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+O` | Sfoglia |
| `F5` | Aggiorna (reload directory) |
| `F4` | Toggle preview panel |
| `F8` | Valida |
| `Delete` | Delete selected pages |
| `Ctrl+S` | Salva modifiche |
| `Alt+↑` / `Alt+↓` | Move page up/down |
| `Escape` | Close preview / close menu / close dialog |
| `Ctrl++` / `Ctrl+-` | Zoom in/out |
| `Ctrl+A` | Select all (in file list or page list) |

Implemented via `FormKeyDown` (already partially wired for Escape).

---

## 8. Zoom

Already implemented via `ZoomScroll` (`TTrackBar`) + `TimerDebounceZoom`. Changes needed:
- Min = 48, Max = 320, Step = 8 (match mockup).
- Default = 128 (currently 96).
- Show current value as a label next to the slider.
- Mouse wheel on the trackbar already works.

---

## 9. Theme (light / dark)

Implement via two `TBitmap`s or a global record of colors swapped when `Visualizza > Tema chiaro / scuro` is clicked.
Store preference in `TIniFile` or `TConfigStorage`. On first run, detect system theme via LCL widgetset.

---

## 10. Data model for in-memory editing

Add a record or class to track the preview state:

```pascal
type
  TPageState = record
    Name: string;      // entry name inside CBZ
    Image: TLazIntfImage;
    Gone: boolean;     // marked for deletion
  end;

  TChangeKind = (ckDeleted, ckMoved);

  TChange = record
    Kind: TChangeKind;
    PageName: string;
  end;
```

- `FPages: array of TPageState` — current working copy.
- `FBaseline: array of TPageState` — snapshot at open time.
- `FChanges: array of TChange` — pending change log.
- `FRenumber: boolean` — whether to renumber on save.

---

## 11. Save / Revert workflow

**Save** (`Ctrl+S` or "Salva modifiche"):
1. Remove `gone` entries.
2. If `FRenumber`, rename survivors `page_NNNN.ext`.
3. Build new ZIP (using `TZipper`) with updated entries.
4. Optionally rename old file to `_OLD.cbz`.
5. Reset `FChanges`, `FRenumber := True`, update `FBaseline`.

**Revert** ("Annulla"):
1. Restore `FPages` from `FBaseline`.
2. Clear `FChanges`, `FRenumber := True`, clear selection.
3. Re-render.

---

## 12. Icons

The mockup uses inline SVG for toolbar buttons, menu items, and the app icon.
Replace these with `TImageList`-based icons (16×16 for menus, 24×24 for toolbars, 16×16 for window icon).
Either load from `.png` resources or draw programmatically with `TCanvas`.

---

## 13. Implementation order (recommended)

| Step | What |
|------|------|
| 1 | **Window chrome**: Title bar, menu bar, toolbar, status bar — structural `.lfm` changes only |
| 2 | **Context menus**: Populate `PMFiles` fully; add `PMPages` for the page list |
| 3 | **Keyboard shortcuts**: Add all to `FormKeyDown` |
| 4 | **Theme toggle**: Light/dark color swap |
| 5 | **In-memory model**: `TPageState`, `TChange`, baseline snapshot on preview open |
| 6 | **Stage bar**: Show/hide based on `FChanges`, wire save/revert |
| 7 | **Page operations**: Delete, move, sort, reverse, renumber |
| 8 | **Drag-and-drop reorder** |
| 9 | **Delete rows dialog** (ranges) — `dlgRows` |
| 10 | **Validate dialog** — `dlgValidate` |
| 11 | **Remove ComicInfo.xml dialog** — `dlgComicInfo` |
| 12 | **Convert WebP dialog** — `dlgWebp` |
| 13 | **Merge chapters dialog** — `dlgMerge` |
| 14 | **Find similar dialog** — `dlgSimilar` |
| 15 | **Delete by ID dialog** — `dlgById` |

Steps 1–4 are pure UI, 5–8 are the core editing workflow, 9–15 add the operation dialogs one by one.
