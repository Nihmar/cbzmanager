"""Delete pages from CBZ files by explicit ID (``filename:entry_name``)."""

from __future__ import annotations

import os
from collections import defaultdict
from io import BytesIO
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

from rich.console import Console
from rich.progress import BarColumn, Progress, SpinnerColumn, TaskProgressColumn, TextColumn

from cbz_manager.delete_pages import _is_image

console = Console()


def _parse_ids(
    ids_str: str | None = None,
    ids_file: str | None = None,
) -> dict[str, set[str]]:
    """Parse page IDs from CSV string and/or file.

    Each ID must have the format ``filename:entry_name``.
    Returns ``{filename: {entry_name, ...}}``.
    """
    result: dict[str, set[str]] = defaultdict(set)

    if ids_str:
        for part in ids_str.split(","):
            part = part.strip()
            if not part:
                continue
            if ":" not in part:
                raise ValueError(f"Invalid ID format (missing ':'): {part!r}")
            filename, entry = part.split(":", 1)
            filename = filename.strip()
            entry = entry.strip()
            if not filename or not entry:
                raise ValueError(f"Invalid ID: {part!r}")
            result[filename].add(entry)

    if ids_file:
        filepath = Path(ids_file)
        if not filepath.is_file():
            raise FileNotFoundError(f"IDs file not found: {ids_file}")
        for line in filepath.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if ":" not in line:
                raise ValueError(f"Invalid ID format in file: {line!r}")
            filename, entry = line.split(":", 1)
            filename = filename.strip()
            entry = entry.strip()
            if not filename or not entry:
                raise ValueError(f"Invalid ID in file: {line!r}")
            result[filename].add(entry)

    if not result:
        raise ValueError("No IDs provided (use --ids or --ids-file)")

    return dict(result)


def _delete_ids_from_cbz(
    cbz_path: Path,
    entries_to_delete: set[str],
    delete: bool,
) -> tuple[bool, int]:
    """Remove exact entry names from a CBZ file and renumber sequentially.

    Args:
        cbz_path: Path to the CBZ file.
        entries_to_delete: Exact entry names to remove.
        delete: If True rewrite in-place; otherwise keep ``_OLD.cbz``.

    Returns:
        ``(changed, pages_removed)``.
    """
    with BytesIO() as buf:
        with open(cbz_path, "rb") as f:
            buf.write(f.read())

        all_entries: list[tuple[str, bytes]] = []
        with ZipFile(buf, "r") as zr:
            for name in zr.namelist():
                if name.lower() == "comicinfo.xml":
                    continue
                all_entries.append((name, zr.read(name)))

        images = [(name, data) for name, data in all_entries if _is_image(name)]
        non_images = [(name, data) for name, data in all_entries if not _is_image(name)]

        kept_images: list[tuple[str, bytes]] = []
        removed = 0
        for name, data in images:
            if name in entries_to_delete:
                removed += 1
            else:
                kept_images.append((name, data))

        if removed == 0:
            return False, 0

        total_kept = len(kept_images)
        padding = max(3, len(str(total_kept)))

        new_entries: list[tuple[str, bytes]] = list(non_images)
        for page_num, (orig_name, data) in enumerate(kept_images, start=1):
            ext = Path(orig_name).suffix.lower()
            new_name = f"page_{page_num:0{padding}d}{ext}"
            new_entries.append((new_name, data))

        out_buf = BytesIO()
        with ZipFile(out_buf, "w", ZIP_DEFLATED, compresslevel=9) as zw:
            for name, data in new_entries:
                zw.writestr(name, data, compress_type=ZIP_DEFLATED, compresslevel=9)

        new_data = out_buf.getvalue()

    if delete:
        with open(cbz_path, "wb") as f:
            f.write(new_data)
    else:
        old_path = cbz_path.with_stem(cbz_path.stem + "_OLD")
        os.rename(cbz_path, old_path)
        with open(cbz_path, "wb") as f:
            f.write(new_data)

    return True, removed


def delete_pages_by_id(
    directory: Path,
    ids_str: str | None = None,
    ids_file: str | None = None,
    delete: bool = False,
) -> int:
    """Delete specific page entries by ID from CBZ files.

    Returns exit code (0 = ok).
    """
    page_map = _parse_ids(ids_str, ids_file)
    cbz_files = sorted(directory.glob("*.cbz"))
    if not cbz_files:
        console.print(f"[yellow]No .cbz files found in {directory}[/yellow]")
        return 0

    console.print(f"[dim]Will delete pages from {len(cbz_files)} CBZ file(s)[/dim]")

    total_removed = 0
    modified_count = 0

    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        BarColumn(),
        TaskProgressColumn(),
        console=console,
    ) as progress:
        task = progress.add_task("Processing...", total=len(cbz_files))

        for cbz in cbz_files:
            progress.update(task, description=f"Processing {cbz.name}")
            try:
                entries_for_file = page_map.get(cbz.name, set())
                if not entries_for_file:
                    progress.advance(task)
                    continue

                changed, removed = _delete_ids_from_cbz(cbz, entries_for_file, delete)
                if changed:
                    total_removed += removed
                    modified_count += 1
                    console.print(
                        f"  [green]✓[/green] {cbz.name}: removed {removed} page(s)"
                    )
                else:
                    console.print(f"  [dim]- {cbz.name}: no matching pages[/dim]")
            except Exception as exc:
                console.print(f"  [red]✗ {cbz.name}: {exc}[/red]")
            progress.advance(task)

    console.print()
    console.print("[bold]Summary:[/bold]")
    console.print(f"  Modified:  [green]{modified_count}[/green]")
    console.print(f"  Removed:   [green]{total_removed}[/green] page(s)")

    return 0
