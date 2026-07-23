# cbzmanager

A FreePascal / Lazarus GUI application for managing CBZ (Comic Book ZIP) files.

Port in progress — the reference Python CLI implementation lives in `porting/cbz_manager/`.

## Planned operations

- **validate** — Verify CBZ files are valid ZIP archives with non-corrupted images (supports `.webp`)
- **convert-webp** — Convert images to WebP (quality 75%) only if smaller; filter `ComicInfo.xml`; rename to `page_NNNN.*`; backup originals as `_OLD.cbz` or delete
- **merge** — Merge chapter CBZ files (`Title - NNNN.cbz`) into volumes (`Title VNNN.cbz`); auto-calculate CPV; supports `--force`, `--chapters`, `--chapters-per-volume`
- **delete-pages** — Delete pages by 1-indexed position (sorted alphabetically); renumber survivors
- **find-similar** — Find similar pages across CBZ files using 64-bit difference hashing; extract groups
- **delete-pages-by-id** — Delete entries by `filename.cbz:entry_name.ext` ID (CSV or file); renumber survivors

All operations filter out `ComicInfo.xml` and rename remaining images to `page_NNNN.*`.

## Reference

The Python CLI in `porting/cbz_manager/` is the reference implementation with full tests.
