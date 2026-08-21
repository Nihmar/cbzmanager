"""Convert images inside CBZ files to WebP format, keeping originals only if smaller."""

from __future__ import annotations

import os
import shutil
import zipfile
from io import BytesIO
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

from PIL import Image
from rich.console import Console
from rich.progress import Progress, SpinnerColumn, BarColumn, TextColumn, TaskProgressColumn

WEBP_QUALITY = 75
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".tif"}
WEBP_EXT = ".webp"

console = Console()


def _is_convertible(name: str) -> bool:
    return Path(name).suffix.lower() in IMAGE_EXTENSIONS


def _convert_image_to_webp(data: bytes, quality: int = WEBP_QUALITY) -> tuple[bytes, bool]:
    """Convert image bytes to WebP. Returns (webp_data, was_smaller)."""
    original_size = len(data)
    try:
        img = Image.open(BytesIO(data))
        if img.mode in ("RGBA", "LA"):
            pass
        elif img.mode != "RGB":
            img = img.convert("RGB")

        buf = BytesIO()
        img.save(buf, format="WEBP", quality=quality, method=6, exif=b"")
        webp_data = buf.getvalue()

        if len(webp_data) < original_size:
            return webp_data, True
        return data, False
    except Exception:
        return data, False


def _process_cbz(cbz_path: Path, delete: bool) -> tuple[bool, int, int]:
    """Process a single CBZ file. Returns (changed, original_size, new_size)."""
    original_size = cbz_path.stat().st_size

    with BytesIO() as buf:
        with open(cbz_path, "rb") as f:
            buf.write(f.read())

        # Read all entries, skipping ComicInfo.xml
        entries: list[tuple[str, bytes]] = []
        with ZipFile(buf, "r") as zr:
            for name in zr.namelist():
                if name.lower() == "comicinfo.xml":
                    continue
                entries.append((name, zr.read(name)))

        # Convert images and rename sequentially
        new_entries: list[tuple[str, bytes]] = []
        converted_count = 0

        # Determine padding from total entries
        total_entries = len(entries)
        padding = max(3, len(str(total_entries)))

        page_num = 0
        for name, data in entries:
            if _is_convertible(name):
                webp_data, was_smaller = _convert_image_to_webp(data)
                if was_smaller:
                    page_num += 1
                    new_name = f"page_{page_num:0{padding}d}.webp"
                    new_entries.append((new_name, webp_data))
                    converted_count += 1
                    continue
            page_num += 1
            ext = Path(name).suffix.lower()
            new_name = f"page_{page_num:0{padding}d}{ext}"
            new_entries.append((new_name, data))

        if converted_count == 0:
            return False, original_size, original_size

        # Write new CBZ
        out_buf = BytesIO()
        with ZipFile(out_buf, "w", ZIP_DEFLATED, compresslevel=9) as zw:
            for name, data in new_entries:
                zw.writestr(name, data, compress_type=ZIP_DEFLATED, compresslevel=9)

        new_data = out_buf.getvalue()
        new_size = len(new_data)

    # Write to disk
    if delete:
        with open(cbz_path, "wb") as f:
            f.write(new_data)
    else:
        old_path = cbz_path.with_stem(cbz_path.stem + "_OLD")
        os.rename(cbz_path, old_path)
        with open(cbz_path, "wb") as f:
            f.write(new_data)

    return True, original_size, new_size


def convert_webp(directory: Path, delete: bool = False) -> int:
    """Convert all CBZ files in a directory to WebP format."""
    cbz_files = sorted(directory.glob("*.cbz"))
    if not cbz_files:
        console.print(f"[yellow]No .cbz files found in {directory}[/yellow]")
        return 0

    console.print(f"[dim]Found {len(cbz_files)} CBZ file(s)[/dim]")

    total_saved = 0
    converted_files = 0
    skipped_files = 0

    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        BarColumn(),
        TaskProgressColumn(),
        console=console,
    ) as progress:
        task = progress.add_task("Converting...", total=len(cbz_files))

        for cbz in cbz_files:
            progress.update(task, description=f"Converting {cbz.name}")
            try:
                changed, orig, new = _process_cbz(cbz, delete)
                if changed:
                    saved = orig - new
                    total_saved += saved
                    converted_files += 1
                    console.print(
                        f"  [green]✓[/green] {cbz.name}: "
                        f"{orig / 1024 / 1024:.1f}MB -> {new / 1024 / 1024:.1f}MB "
                        f"([green]-{saved / 1024 / 1024:.1f}MB[/green])"
                    )
                else:
                    skipped_files += 1
                    console.print(f"  [dim]- {cbz.name}: no space savings, skipped[/dim]")
            except Exception as exc:
                console.print(f"  [red]✗ {cbz.name}: {exc}[/red]")
            progress.advance(task)

    console.print()
    console.print(f"[bold]Summary:[/bold]")
    console.print(f"  Converted: [green]{converted_files}[/green]")
    console.print(f"  Skipped:   [dim]{skipped_files}[/dim]")
    console.print(f"  Saved:     [green]{total_saved / 1024 / 1024:.1f}MB[/green]")

    return 0
