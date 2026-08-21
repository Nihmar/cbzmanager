"""Validate CBZ files: check ZIP integrity, non-empty, and image readability."""

from __future__ import annotations

import sys
import zipfile
from io import BytesIO
from pathlib import Path

from PIL import Image
from rich.console import Console
from rich.table import Table

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".tif", ".webp"}

console = Console()


def _is_image(name: str) -> bool:
    return Path(name).suffix.lower() in IMAGE_EXTENSIONS


class ValidationResult:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.errors: list[str] = []
        self.warnings: list[str] = []
        self.image_count = 0

    @property
    def ok(self) -> bool:
        return len(self.errors) == 0


def validate_cbz(path: Path) -> ValidationResult:
    """Validate a single CBZ file. Returns a result with any errors found."""
    result = ValidationResult(path)

    if path.stat().st_size == 0:
        result.errors.append("File is empty (0 bytes)")
        return result

    try:
        with zipfile.ZipFile(path, "r") as zf:
            bad = zf.testzip()
            if bad is not None:
                result.errors.append(f"Corrupted entry in ZIP: {bad}")
                return result

            names = zf.namelist()
            if not names:
                result.errors.append("ZIP archive is empty (no entries)")
                return result

            image_names = [n for n in names if _is_image(n)]
            if not image_names:
                result.warnings.append("No image files found in archive")
                return result

            for img_name in image_names:
                data = zf.read(img_name)
                try:
                    img = Image.open(BytesIO(data))
                    img.verify()
                    result.image_count += 1
                except Exception as exc:
                    result.errors.append(f"Corrupted image '{img_name}': {exc}")

    except zipfile.BadZipFile as exc:
        result.errors.append(f"Invalid ZIP file: {exc}")
    except OSError as exc:
        result.errors.append(f"OS error reading file: {exc}")

    return result


def validate(directory: Path) -> int:
    """Validate all CBZ files in a directory. Returns exit code (0=ok)."""
    cbz_files = sorted(directory.glob("*.cbz"))
    if not cbz_files:
        console.print(f"[yellow]No .cbz files found in {directory}[/yellow]")
        return 0

    results: list[ValidationResult] = []
    for cbz in cbz_files:
        console.print(f"[dim]Checking {cbz.name}...[/dim]")
        results.append(validate_cbz(cbz))

    # Print results
    table = Table(title="Validation Results", show_lines=True)
    table.add_column("File", style="cyan", no_wrap=True)
    table.add_column("Images", justify="right")
    table.add_column("Status")
    table.add_column("Details", style="dim")

    ok_count = 0
    fail_count = 0
    invalid: list[ValidationResult] = []

    for r in results:
        if r.ok:
            status = "[green]OK[/green]"
            details = ""
            ok_count += 1
        else:
            status = "[red]FAIL[/red]"
            details = "; ".join(r.errors)
            fail_count += 1
            invalid.append(r)

        if r.warnings:
            details = "; ".join(r.warnings) + (f"; {details}" if details else "")

        table.add_row(r.path.name, str(r.image_count) if r.image_count else "-", status, details)

    console.print(table)
    console.print()

    if invalid:
        console.print("[bold red]Invalid files:[/bold red]")
        for r in invalid:
            console.print(f"  [red]✗ {r.path.name}[/red]")
            for err in r.errors:
                console.print(f"    [dim]{err}[/dim]")
        console.print()

    console.print(f"[green]Valid:[/green] {ok_count}  [red]Invalid:[/red] {fail_count}  [dim]Total:[/dim] {len(results)}")

    return 1 if fail_count > 0 else 0
