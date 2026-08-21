"""Find similar pages within and across CBZ files using difference hashing."""

from __future__ import annotations

import shutil
from io import BytesIO
from pathlib import Path
from zipfile import ZipFile

from PIL import Image
from rich.console import Console
from rich.progress import BarColumn, Progress, SpinnerColumn, TaskProgressColumn, TextColumn

from cbz_manager.delete_pages import _is_image

DEFAULT_HASH_SIZE = 8
DEFAULT_THRESHOLD = 10

console = Console()


def _dhash(image: Image.Image, hash_size: int = DEFAULT_HASH_SIZE) -> int:
    """Compute a 64-bit difference hash for *image*.

    Algorithm:
      1. Resize to ``(hash_size + 1, hash_size)``.
      2. Convert to grayscale (L).
      3. Compare adjacent horizontal pixels.
    """
    img = image.convert("L").resize((hash_size + 1, hash_size), Image.LANCZOS)
    pixels = list(img.getdata())
    w = hash_size + 1
    h = hash_size

    hash_val = 0
    for y in range(h):
        for x in range(hash_size):
            bit = 1 if pixels[y * w + x] > pixels[y * w + x + 1] else 0
            hash_val = (hash_val << 1) | bit
    return hash_val


def _hamming(a: int, b: int) -> int:
    """Hamming distance between two 64-bit hashes."""
    return (a ^ b).bit_count()


def _collect_images(
    directory: Path,
) -> list[tuple[str, str, int, bytes]]:
    """Scan all CBZ files and return image entries.

    Each entry is ``(cbz_name, entry_name, hash, data)``.
    """
    cbz_files = sorted(directory.glob("*.cbz"))
    if not cbz_files:
        console.print(f"[yellow]No .cbz files found in {directory}[/yellow]")
        return []

    results: list[tuple[str, str, int, bytes]] = []

    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        BarColumn(),
        TaskProgressColumn(),
        console=console,
    ) as progress:
        task = progress.add_task("Hashing images...", total=len(cbz_files))

        for cbz in cbz_files:
            progress.update(task, description=f"Hashing {cbz.name}")
            try:
                with ZipFile(cbz, "r") as zr:
                    for entry_name in zr.namelist():
                        if entry_name.lower() == "comicinfo.xml":
                            continue
                        if not _is_image(entry_name):
                            continue
                        data = zr.read(entry_name)
                        img = Image.open(BytesIO(data))
                        hash_val = _dhash(img)
                        results.append((cbz.name, entry_name, hash_val, data))
            except Exception as exc:
                console.print(f"  [red]✗ {cbz.name}: {exc}[/red]")
            progress.advance(task)

    return results


def _group_similar(
    entries: list[tuple[str, str, int, bytes]],
    threshold: int,
) -> list[list[tuple[str, str, bytes]]]:
    """Group entries by hash similarity.

    Returns groups that have **at least 2 members**.
    """
    n = len(entries)
    assigned = [False] * n
    groups: list[list[tuple[str, str, bytes]]] = []

    for i in range(n):
        if assigned[i]:
            continue
        group: list[tuple[str, str, bytes]] = [
            (entries[i][0], entries[i][1], entries[i][3])
        ]
        assigned[i] = True
        for j in range(i + 1, n):
            if assigned[j]:
                continue
            dist = _hamming(entries[i][2], entries[j][2])
            if dist < threshold:
                group.append((entries[j][0], entries[j][1], entries[j][3]))
                assigned[j] = True

        if len(group) >= 2:
            groups.append(group)

    return groups


def _sanitize(name: str) -> str:
    """Replace characters that are problematic in filenames."""
    return name.replace("/", "_").replace(":", "_").replace(" ", "_")


def find_similar(
    directory: Path,
    output_dir: Path,
    threshold: int = DEFAULT_THRESHOLD,
) -> int:
    """Find similar pages across CBZ files and extract grouped copies.

    Args:
        directory: Directory containing CBZ files.
        output_dir: Where to write similarity groups.
        threshold: Maximum Hamming distance for "similar".

    Returns exit code (0 = ok).
    """
    entries = _collect_images(directory)
    if not entries:
        return 0

    console.print(f"  Found [cyan]{len(entries)}[/cyan] image(s) — grouping...")

    groups = _group_similar(entries, threshold)
    if not groups:
        console.print("[yellow]No similar page groups found[/yellow]")
        return 0

    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    console.print(f"  Found [cyan]{len(groups)}[/cyan] similar group(s)")

    for gidx, group in enumerate(groups, start=1):
        group_dir = output_dir / f"similarity_{gidx:03d}"
        group_dir.mkdir(parents=True, exist_ok=True)

        ids: list[str] = []
        for cbz_name, entry_name, data in group:
            safe = f"{_sanitize(cbz_name)}__{entry_name}"
            dest = group_dir / safe
            dest.write_bytes(data)
            ids.append(f"{cbz_name}:{entry_name}")

        (group_dir / "ids.txt").write_text("\n".join(ids) + "\n")

    console.print(f"  Extracted to [cyan]{output_dir}[/cyan]")
    return 0
