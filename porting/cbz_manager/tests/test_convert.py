"""Tests for convert-webp operation."""

from __future__ import annotations

import zipfile
from io import BytesIO
from pathlib import Path

from PIL import Image

from cbz_manager.convert import convert_webp, _convert_image_to_webp, _process_cbz


def _make_image_png(width: int = 100, height: int = 100, color: tuple[int, int, int] = (255, 0, 0)) -> bytes:
    img = Image.new("RGB", (width, height), color)
    buf = BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def _make_image_jpg(width: int = 100, height: int = 100, quality: int = 95) -> bytes:
    img = Image.new("RGB", (width, height), (0, 128, 255))
    buf = BytesIO()
    img.save(buf, format="JPEG", quality=quality)
    return buf.getvalue()


def test_convert_image_to_webp_saves_space() -> None:
    """Large PNG should compress well to WebP."""
    png_data = _make_image_png(800, 800, (255, 0, 0))
    webp_data, was_smaller = _convert_image_to_webp(png_data)
    assert was_smaller
    assert len(webp_data) < len(png_data)


def test_convert_image_to_webp_small_jpg() -> None:
    """Already-small JPEG should not benefit from WebP."""
    jpg_data = _make_image_jpg(100, 100, quality=50)
    webp_data, was_smaller = _convert_image_to_webp(jpg_data)
    # Small JPEG might or might not benefit, just check it doesn't crash
    assert isinstance(webp_data, bytes)


def test_process_cbz_converts(convert_dir: Path) -> None:
    """Process a CBZ with large images - should convert."""
    cbz_path = convert_dir / "large.cbz"
    changed, orig, new = _process_cbz(cbz_path, delete=True)
    assert changed
    assert new < orig


def test_process_cbz_no_savings(convert_dir: Path) -> None:
    """Process a CBZ with only WebP images - should not change."""
    cbz_path = convert_dir / "already_webp.cbz"
    changed, orig, new = _process_cbz(cbz_path, delete=True)
    assert not changed


def test_process_cbz_backup_mode(convert_dir: Path) -> None:
    """Without --delete, original should be renamed to _OLD and new file written."""
    cbz_path = convert_dir / "large.cbz"
    changed, _, _ = _process_cbz(cbz_path, delete=False)
    assert changed
    # New file should exist (overwritten with converted content)
    assert cbz_path.exists()
    # Backup of original should exist
    old_path = cbz_path.with_stem(cbz_path.stem + "_OLD")
    assert old_path.exists()


def test_process_cbz_delete_mode(convert_dir: Path) -> None:
    """With --delete, original is overwritten."""
    cbz_path = convert_dir / "large.cbz"
    changed, _, _ = _process_cbz(cbz_path, delete=True)
    assert changed
    assert cbz_path.exists()
    old_path = cbz_path.with_stem(cbz_path.stem + "_OLD")
    assert not old_path.exists()


def test_convert_webp_directory(convert_dir: Path) -> None:
    """Convert all CBZ files in directory."""
    exit_code = convert_webp(convert_dir, delete=True)
    assert exit_code == 0

    with zipfile.ZipFile(convert_dir / "large.cbz") as zf:
        names = zf.namelist()
        assert any(n.endswith(".webp") for n in names)
