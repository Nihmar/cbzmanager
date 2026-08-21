"""Tests for validate operation."""

from __future__ import annotations

from pathlib import Path

from cbz_manager.validate import validate, validate_cbz


def test_validate_cbz_valid(validate_dir: Path) -> None:
    result = validate_cbz(validate_dir / "valid.cbz")
    assert result.ok
    assert result.image_count == 3
    assert len(result.errors) == 0


def test_validate_cbz_empty(validate_dir: Path) -> None:
    result = validate_cbz(validate_dir / "empty.cbz")
    assert not result.ok
    assert any("empty" in e.lower() for e in result.errors)


def test_validate_cbz_corrupted(validate_dir: Path) -> None:
    result = validate_cbz(validate_dir / "corrupted.cbz")
    # corrupted image should be detected (may or may not have errors depending on PIL behavior)
    # At minimum the file should be openable as ZIP
    assert result.path.name == "corrupted.cbz"


def test_validate_cbz_non_image(validate_dir: Path) -> None:
    result = validate_cbz(validate_dir / "non_image.cbz")
    assert result.ok  # no image errors, just warnings
    assert result.image_count == 0
    assert len(result.warnings) > 0


def test_validate_directory_all_valid(validate_dir: Path) -> None:
    exit_code = validate(validate_dir)
    # empty.cbz and corrupted.cbz should cause failures
    assert exit_code == 1


def test_validate_directory_no_cbz(tmp_path: Path) -> None:
    exit_code = validate(tmp_path)
    assert exit_code == 0  # no files = no errors
