# CBZ Manager

CLI utility for managing manga CBZ (Comic Book ZIP) files.

## Features

- **validate** — Verify CBZ files are valid ZIP archives with non-corrupted images (supports `.webp` too)
- **convert-webp** — Convert images to WebP format (quality 75%) with space savings; filters `ComicInfo.xml`; renames images sequentially as `page_NNNN.*`
- **merge** — Merge chapter CBZ files into volumes based on existing volume average; supports `--force`, `--chapters`, and `--chapters-per-volume`
- **delete-pages** — Delete pages by position from CBZ files (sorted alphabetically); renumbers remaining pages
- **find-similar** — Find similar pages across CBZ files using difference hashing; extracts grouped copies to specified directory
- **delete-pages-by-id** — Delete specific page entries by ID (`filename:entry_name`) from CBZ files

## Installation

Requires [uv](https://docs.astral.sh/uv/) package manager.

```bash
uv sync
```

## Usage

```bash
# Show version
uv run cbz-manager --version

# Validate all CBZ files in a directory
uv run cbz-manager validate <directory>

# Convert images to WebP (creates _OLD.cbz backups)
uv run cbz-manager convert-webp <directory>

# Convert images to WebP (deletes originals)
uv run cbz-manager convert-webp <directory> --delete

# Merge chapters into volumes
uv run cbz-manager merge <directory>

# Merge and delete original chapter files
uv run cbz-manager merge <directory> --delete

# Merge and append remaining chapters to the last volume
uv run cbz-manager merge <directory> --force

# Merge with exact chapter counts per volume
uv run cbz-manager merge <directory> --chapters 5,6,3

# Merge with fixed chapters per volume
uv run cbz-manager merge <directory> --chapters-per-volume 7

# Delete pages 3 and 5-20 from all CBZ files
uv run cbz-manager <directory> delete-pages --pages "3,5-20"

# Find similar pages and extract them
uv run cbz-manager <directory> find-similar --output ./similar --threshold 10

# Delete specific pages by ID
uv run cbz-manager <directory> delete-pages-by-id --ids "ch01.cbz:page_003.png,ch02.cbz:page_001.jpg"

# Delete pages by ID from a file (one ID per line)
uv run cbz-manager <directory> delete-pages-by-id --ids-file ./ids.txt
```

## Operations

### validate

Checks that all `.cbz` files in the directory are:
- Valid ZIP archives
- Non-empty
- Contain readable, non-corrupted images

Reports valid/invalid files with details.

### convert-webp

Converts images inside CBZ files to WebP format:
- Quality: 75% (fixed)
- Only converts if WebP is smaller than original
- Filters out `ComicInfo.xml` (not an image)
- Renames all images sequentially as `page_NNNN.*`
- Recompresses with maximum ZIP compression (level 9)
- With `--delete`: overwrites original files
- Without `--delete`: renames originals to `_OLD.cbz`

### merge

Merges chapter CBZ files into volumes:

1. Detects chapters (`Title - NNNN.cbz`) and volumes (`Title VNNN.cbz`)
2. Determines chapters per volume (in order of priority):
   - `--chapters N1,N2,...` — exact chapter count per volume (custom list)
   - `--chapters-per-volume N` — fixed override
   - **Automatic**: `chapters_per_volume = (lowest_chapter - 1) / num_volumes`
   - If no volumes exist, defaults to **7** chapters per volume
3. Groups chapters into batches
4. Creates new volumes starting from `max_volume + 1`
5. Skips if not enough chapters for a full volume
6. With `--force`: remaining chapters are appended to the last volume instead of skipped
7. Filters out `ComicInfo.xml` and renames images sequentially as `page_NNNN.*`

Flags:
| Flag | Description |
|------|-------------|
| `--delete` | Delete original chapters instead of renaming to `_OLD.cbz` |
| `--force` | Append remaining chapters below threshold to the last volume |
| `--chapters N1,N2,...` | Exact chapter counts per volume (e.g. `5,6,3`) |
| `--chapters-per-volume N` | Override the auto-calculated chapters-per-volume |

Examples:
- Chapters: 001-006 (6 chapters), Volumes: V001-V002 (2 volumes)
- Average: (7-1)/2 = 3 chapters per volume
- Result: V003 (ch 1-3), V004 (ch 4-6)
- With `--force` on 7 chapters (avg=3): V003 (ch 1-3), V004 (ch 4-7)
- With `--chapters 2,4` (6 chapters): V003 (ch 1-2), V004 (ch 3-6)
- With `--chapters-per-volume 3`: same as automatic average

### delete-pages

Deletes pages by position from all CBZ files in a directory:

1. Sorts all image entries alphabetically within each CBZ
2. Removes the specified page positions (e.g. pages 3 and 5-20)
3. Renumbers remaining pages sequentially as `page_NNNN.*`
4. Filters out `ComicInfo.xml`
5. With `--delete`: overwrites original files
6. Without `--delete`: renames originals to `_OLD.cbz`

### find-similar

Finds similar pages across CBZ files using 64-bit difference hashing (dhash):

1. Scans all images in all CBZ files
2. Computes a perceptual hash for each image
3. Groups images by Hamming distance similarity (threshold: default 10)
4. Extracts groups of 2+ similar pages to `<output>/similarity_NNN/`
5. Each group contains the extracted files and an `ids.txt` with IDs

Use the `ids.txt` output with `delete-pages-by-id` to delete selected groups.

### delete-pages-by-id

Deletes specific page entries by exact match from CBZ files:

1. Accepts IDs in `filename:entry_name` format (e.g. `ch01.cbz:page_003.png`)
2. IDs can be provided inline (`--ids`) or from a file (`--ids-file`)
3. Removes matching entries and renumbers remaining pages sequentially
4. Filters out `ComicInfo.xml`
5. With `--delete`: overwrites original files
6. Without `--delete`: renames originals to `_OLD.cbz`

## Testing

```bash
# Run all tests
uv run pytest

# Run with coverage
uv run pytest --cov=cbz_manager

# Run specific test file
uv run pytest tests/test_validate.py
```

Test data is generated dynamically before each test.

## Project Structure

```
cbz_manager/
├── pyproject.toml
├── README.md
├── AGENTS.md
├── .gitignore
├── tests/
│   ├── conftest.py              # Fixtures with dynamic test data generation
│   ├── test_validate.py
│   ├── test_convert.py
│   ├── test_merge.py
│   ├── test_delete_pages.py
│   ├── test_find_similar.py
│   ├── test_delete_by_id.py
│   ├── validate/                # Generated test data for validate tests
│   ├── convert/                 # Generated test data for convert tests
│   └── merge_insufficient/      # Generated test data for merge tests
└── src/
    └── cbz_manager/
        ├── __init__.py           # Version: 0.1.0
        ├── __main__.py
        ├── cli.py                # Argument parsing and operation dispatch
        ├── validate.py           # ZIP/image validation logic (supports .webp)
        ├── convert.py            # WebP conversion with PIL
        ├── merge.py              # Chapter detection and volume creation
        ├── delete_pages.py       # Delete pages by position; renumbers remaining
        ├── find_similar.py       # Difference-hash based similarity detection
        └── delete_by_id.py       # Delete pages by filename:entry_name ID
```
