"""Merge chapter CBZ files into volumes based on existing volume average."""

from __future__ import annotations

import os
import re
from dataclasses import dataclass, field
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

from rich.console import Console
from rich.table import Table

_CHAPTER_RE = re.compile(r"^(.+)\s-\s(\d+)(?:_\d+)*\.cbz$", re.IGNORECASE)
_SPECIAL_RE = re.compile(r"^(.+)\s- ([A-Za-z][A-Za-z0-9]*)(?:_\d+)*\.cbz$", re.IGNORECASE)
_VOLUME_RE = re.compile(r"^(.+)\s(V\d+)\.cbz$", re.IGNORECASE)

console = Console()


@dataclass
class _VolumeSpec:
    output_path: Path
    chapter_paths: list[Path]
    num_pages: int = 0


@dataclass
class _SeriesPlan:
    series_name: str
    ch_list: list = field(default_factory=list)
    volumes: list[_VolumeSpec] = field(default_factory=list)
    ch_index: int = 0
    remaining: int = 0


def _parse_cbz_files(directory: Path) -> tuple[list[tuple[str, int, Path]], list[tuple[str, str, Path]]]:
    """Parse CBZ files into chapters and volumes.

    Returns:
        (chapters, volumes) where each chapter is (series, number, path)
        and each volume is (series, volume_tag, path).

    Special chapters (e.g. ``- SP01``) are assigned sequential numbers
    after the highest regular chapter for their series.
    """
    chapters: list[tuple[str, int, Path]] = []
    volumes: list[tuple[str, str, Path]] = []
    specials: list[tuple[str, str, Path]] = []

    for cbz in sorted(directory.glob("*.cbz")):
        m_ch = _CHAPTER_RE.match(cbz.name)
        if m_ch:
            chapters.append((m_ch.group(1), int(m_ch.group(2)), cbz))
            continue
        m_sp = _SPECIAL_RE.match(cbz.name)
        if m_sp:
            specials.append((m_sp.group(1), m_sp.group(2), cbz))
            continue
        m_vo = _VOLUME_RE.match(cbz.name)
        if m_vo:
            volumes.append((m_vo.group(1), m_vo.group(2), cbz))

    if specials:
        special_map: dict[str, list[tuple[str, str, Path]]] = {}
        for sp_series, sp_tag, sp_path in specials:
            special_map.setdefault(sp_series, []).append((sp_tag, sp_path))

        max_by_series: dict[str, int] = {}
        for series, num, _ in chapters:
            max_by_series[series] = max(max_by_series.get(series, 0), num)

        for series, sp_list in special_map.items():
            next_num = max_by_series.get(series, 0) + 1
            for _, sp_path in sp_list:
                chapters.append((series, next_num, sp_path))
                next_num += 1

    return chapters, volumes


def _max_volume_number(volumes: list[tuple[str, str, Path]]) -> int:
    """Extract the highest volume number from existing volumes."""
    max_num = 0
    for _, vol_tag, _ in volumes:
        m = re.search(r"(\d+)$", vol_tag)
        if m:
            max_num = max(max_num, int(m.group(1)))
    return max_num


def _merge_cbz_files(source_paths: list[Path], output_path: Path) -> int:
    """Merge multiple CBZ files into a single flat CBZ with sequential image names.

    Returns the number of images written.
    """
    total_images = 0
    for cbz_path in source_paths:
        with ZipFile(cbz_path, "r") as zr:
            for name in zr.namelist():
                if name.lower() != "comicinfo.xml":
                    total_images += 1

    padding = max(3, len(str(total_images)))

    page_num = 0
    with ZipFile(output_path, "w", ZIP_DEFLATED, compresslevel=9) as zw:
        for cbz_path in source_paths:
            with ZipFile(cbz_path, "r") as zr:
                for img_name in sorted(zr.namelist()):
                    if img_name.lower() == "comicinfo.xml":
                        continue
                    data = zr.read(img_name)
                    page_num += 1
                    ext = Path(img_name).suffix.lower()
                    new_name = f"page_{page_num:0{padding}d}{ext}"
                    zw.writestr(new_name, data, compress_type=ZIP_DEFLATED, compresslevel=9)
    return page_num


def merge(
    directory: Path,
    delete: bool = False,
    force: bool = False,
    chapters_list: list[int] | None = None,
    chapters_per_volume_int: int | None = None,
) -> int:
    """Merge chapter CBZ files into volumes.

    Args:
        directory: Path containing CBZ files.
        delete: If True, delete original chapters; otherwise rename to _OLD.
        force: If True, append remaining chapters to the last volume.
        chapters_list: Exact chapter counts per volume, e.g. [5, 6, 3].
        chapters_per_volume_int: Fixed chapters-per-volume override.
    """
    console.print(f"[dim]Scanning {directory}...[/dim]")
    chapters, volumes = _parse_cbz_files(directory)

    if not chapters:
        console.print("[yellow]No chapter files found (pattern: 'Title - NNNN.cbz' or 'Title - SP01.cbz')[/yellow]")
        return 0

    if volumes:
        console.print(f"  Found [cyan]{len(chapters)}[/cyan] chapter(s), [cyan]{len(volumes)}[/cyan] volume(s)")
    else:
        if chapters_list is not None:
            console.print(f"  Found [cyan]{len(chapters)}[/cyan] chapter(s), no volumes yet — using custom chapter list")
        elif chapters_per_volume_int is not None:
            console.print(f"  Found [cyan]{len(chapters)}[/cyan] chapter(s), no volumes yet — using [cyan]{chapters_per_volume_int}[/cyan] chapters per volume")
        else:
            console.print(f"  Found [cyan]{len(chapters)}[/cyan] chapter(s), no volumes yet — using default [cyan]7[/cyan] chapters per volume")

    series_map: dict[str, list[tuple[str, int, Path]]] = {}
    for ch in chapters:
        series_map.setdefault(ch[0], []).append(ch)

    volume_map: dict[str, list[tuple[str, str, Path]]] = {}
    for vo in volumes:
        volume_map.setdefault(vo[0], []).append(vo)

    all_series = sorted(set(list(series_map.keys()) + list(volume_map.keys())))

    table = Table(title="Merge Plan", show_lines=True)
    table.add_column("Series", style="cyan")
    table.add_column("Chapters", justify="right")
    table.add_column("Volumes", justify="right")
    table.add_column("Avg", justify="right")
    table.add_column("New Volumes", justify="right")
    table.add_column("Skipped", justify="right")
    table.add_column("Status")

    # ── Phase 1: Plan ─────────────────────────────────────────────────

    series_plans: list[_SeriesPlan] = []
    total_new_volumes = 0

    for series_name in all_series:
        ch_list = sorted(series_map.get(series_name, []), key=lambda x: x[1])
        vo_list = volume_map.get(series_name, [])

        num_chapters = len(ch_list)
        num_volumes = len(vo_list)

        console.print(f"[dim]Processing {series_name}: {num_chapters} chapters, {num_volumes} volumes...[/dim]")

        if chapters_list is not None:
            chapters_per_volume = None
            num_new_volumes = len(chapters_list)
            next_vol = _max_volume_number(vo_list) + 1 if vo_list else 1
        elif chapters_per_volume_int is not None:
            chapters_per_volume = float(chapters_per_volume_int)
            next_vol = _max_volume_number(vo_list) + 1 if vo_list else 1
        elif num_volumes == 0:
            chapters_per_volume = 7.0
            next_vol = 1
        else:
            lowest_chapter = ch_list[0][1]
            chapters_already_in_volumes = lowest_chapter - 1
            chapters_per_volume = chapters_already_in_volumes / num_volumes
            next_vol = _max_volume_number(vo_list) + 1

        plan = _SeriesPlan(series_name=series_name, ch_list=ch_list)

        if num_chapters == 0:
            table.add_row(series_name, "0", str(num_volumes), "-", "-", "0", "[dim]No chapters[/dim]")
            series_plans.append(plan)
            continue

        if chapters_list is not None:
            total_requested = sum(chapters_list)
            if total_requested > num_chapters:
                console.print(
                    f"[red]Error: --chapters sum ({total_requested}) exceeds "
                    f"available chapters ({num_chapters}) for '{series_name}'[/red]"
                )
                return 1

            for vol_idx, count in enumerate(chapters_list):
                if plan.ch_index + count > num_chapters:
                    break
                vol_num = next_vol + vol_idx
                output_path = directory / f"{series_name} V{vol_num:03d}.cbz"
                batch = [ch_list[plan.ch_index + i][2] for i in range(count)]
                plan.volumes.append(_VolumeSpec(output_path=output_path, chapter_paths=batch))
                plan.ch_index += count

            plan.remaining = num_chapters - plan.ch_index

            display_avg = "custom"
            display_new_vol = str(num_new_volumes)
        else:
            if num_chapters < chapters_per_volume:
                table.add_row(
                    series_name,
                    str(num_chapters),
                    str(num_volumes),
                    f"{chapters_per_volume:.1f}",
                    "0",
                    str(num_chapters),
                    "[dim]Not enough chapters[/dim]",
                )
                series_plans.append(plan)
                continue

            num_new_volumes = int(num_chapters / chapters_per_volume)
            if num_new_volumes == 0:
                table.add_row(
                    series_name,
                    str(num_chapters),
                    str(num_volumes),
                    f"{chapters_per_volume:.1f}",
                    "0",
                    str(num_chapters),
                    "[dim]Not enough chapters[/dim]",
                )
                series_plans.append(plan)
                continue

            for vol_idx in range(num_new_volumes):
                vol_num = next_vol + vol_idx
                output_path = directory / f"{series_name} V{vol_num:03d}.cbz"
                batch = [ch_list[plan.ch_index + i][2] for i in range(int(chapters_per_volume))]
                plan.volumes.append(_VolumeSpec(output_path=output_path, chapter_paths=batch))
                plan.ch_index += int(chapters_per_volume)

            remaining_chapters = num_chapters - plan.ch_index
            if remaining_chapters > 0 and force:
                last_spec = plan.volumes[-1]
                start = plan.ch_index - int(chapters_per_volume)
                last_spec.chapter_paths = [ch_list[i][2] for i in range(start, plan.ch_index + remaining_chapters)]
                plan.ch_index += remaining_chapters
            else:
                plan.remaining = remaining_chapters

            display_avg = f"{chapters_per_volume:.1f}"
            display_new_vol = str(num_new_volumes)

        table.add_row(
            series_name,
            str(num_chapters),
            str(num_volumes),
            display_avg,
            display_new_vol,
            str(plan.remaining),
            "[green]Will create[/green]",
        )
        total_new_volumes += len(plan.volumes)
        series_plans.append(plan)

    # Print preview
    if total_new_volumes > 0:
        series_count = len([p for p in series_plans if p.volumes])
        console.print(f"[bold]Merge plan: {total_new_volumes} new volume(s) across {series_count} series[/bold]")
    else:
        console.print("[dim]No volumes to create[/dim]")

    console.print()
    console.print(table)
    console.print()

    # ── Phase 2: Create volumes (with rollback on error) ──────────────

    created_paths: list[Path] = []
    try:
        for plan in series_plans:
            for spec in plan.volumes:
                num_pages = _merge_cbz_files(spec.chapter_paths, spec.output_path)
                spec.num_pages = num_pages
                created_paths.append(spec.output_path)
                console.print(
                    f"  [green]✓[/green] Created {spec.output_path.name} "
                    f"({len(spec.chapter_paths)} chapters, {num_pages} pages)"
                )
    except Exception:
        for p in created_paths:
            try:
                p.unlink()
            except OSError:
                pass
        console.print("[red]Error during merge — created volumes have been removed[/red]")
        return 1

    # ── Phase 3: Cleanup original chapters ────────────────────────────

    for plan in series_plans:
        if plan.ch_index > 0:
            for _, _, ch_path in plan.ch_list[:plan.ch_index]:
                if delete:
                    ch_path.unlink()
                else:
                    old_path = ch_path.with_stem(ch_path.stem + "_OLD")
                    os.rename(ch_path, old_path)

        if plan.remaining > 0:
            if chapters_list is not None:
                console.print(
                    f"  [dim]  {plan.remaining} chapter(s) remaining "
                    f"(beyond --chapters list, skipped)[/dim]"
                )
            else:
                console.print(
                    f"  [dim]  {plan.remaining} chapter(s) remaining "
                    f"(below threshold, skipped)[/dim]"
                )

    created_count = len(created_paths)
    console.print(f"[bold]Created [green]{created_count}[/green] new volume(s)[/bold]")
    return 0
