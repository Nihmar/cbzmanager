"""Delete pages from CBZ files by position, then renumber sequentially."""

from __future__ import annotations

import os
import re
from io import BytesIO
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

from PIL import Image
from rich.console import Console
from rich.progress import BarColumn, Progress, SpinnerColumn, TaskProgressColumn, TextColumn

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".tif", ".webp"}

console = Console()


def _is_image(name: str) -> bool:
    return Path(name).suffix.lower() in IMAGE_EXTENSIONS


def _parse_pages(pages_str: str) -> set[int]:
    """Parse a page specification like ``"3,5-20,22"`` into ``{3,5,6,...,20,22}``.

    Numbers are 1-indexed.
    """
    result: set[int] = set()
    for part in pages_str.split(","):
        part = part.strip()
        if not part:
            continue
        m = re.match(r"^(\d+)(?:-(\d+))?$", part)
        if not m:
            raise ValueError(f"Invalid page specification: {part!r}")
        start = int(m.group(1))
        if m.group(2):
            end = int(m.group(2))
            if start > end:
                raise ValueError(f"Invalid range: {start}-{end} (start > end)")
            result.update(range(start, end + 1))
        else:
            result.add(start)
    return result


def _delete_pages_from_cbz(
    cbz_path: Path, pages_to_delete: set[int], delete: bool
) -> tuple[bool, int]:
    """Remove given page positions from a CBZ file and renumber sequentially.

    Args:
        cbz_path: Path to the CBZ file.
        pages_to_delete: 1-indexed positions to remove.
        delete: If True rewrite in-place; otherwise keep ``_OLD.cbz``.

    Returns:
        ``(changed, pages_removed)``.
    """
    with BytesIO() as buf:
        with open(cbz_path, "rb") as f:
            buf.write(f.read())

        entries: list[tuple[str, bytes]] = []
        with ZipFile(buf, "r") as zr:
            for name in zr.namelist():
                if name.lower() == "comicinfo.xml":
                    continue
                entries.append((name, zr.read(name)))

        images = [(name, data) for name, data in entries if _is_image(name)]
        images.sort(key=lambda x: x[0])

        non_images = [(name, data) for name, data in entries if not _is_image(name)]

        kept: list[tuple[str, bytes]] = []
        removed = 0
        for idx, (name, data) in enumerate(images, start=1):
            if idx in pages_to_delete:
                removed += 1
            else:
                kept.append((name, data))

        if removed == 0:
            return False, 0

        total_kept = len(kept)
        padding = max(3, len(str(total_kept)))

        new_entries: list[tuple[str, bytes]] = list(non_images)
        for page_num, (orig_name, data) in enumerate(kept, start=1):
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


def validate_images_in_cbz(cbz_path: Path) -> bool:
    """Quick check that all entries are readable images."""
    with ZipFile(cbz_path, "r") as zr:
        for name in zr.namelist():
            if _is_image(name):
                try:
                    img = Image.open(BytesIO(zr.read(name)))
                    img.verify()
                except Exception:
                    return False
    return True


def delete_pages(directory: Path, pages_str: str, delete: bool = False) -> int:
    """Delete specified page positions from all CBZ files in *directory*.

    Returns exit code (0 = ok).
    """
    pages_to_delete = _parse_pages(pages_str)
    if not pages_to_delete:
        console.print("[yellow]No pages specified[/yellow]")
        return 0

    cbz_files = sorted(directory.glob("*.cbz"))
    if not cbz_files:
        console.print(f"[yellow]No .cbz files found in {directory}[/yellow]")
        return 0

    console.print(
        f"[dim]Will delete page(s) {sorted(pages_to_delete)} from "
        f"{len(cbz_files)} CBZ file(s)[/dim]"
    )

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
                changed, removed = _delete_pages_from_cbz(cbz, pages_to_delete, delete)
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
