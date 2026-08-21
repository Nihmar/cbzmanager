"""Tests for delete-pages-by-id operation."""

from __future__ import annotations

from io import BytesIO
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

from PIL import Image

from cbz_manager.delete_by_id import _delete_ids_from_cbz, _parse_ids, delete_pages_by_id


def _make_image_png(width: int = 100, height: int = 100, color: tuple[int, int, int] = (255, 0, 0)) -> bytes:
    img = Image.new("RGB", (width, height), color)
    buf = BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def _write_cbz(path: Path, images: dict[str, bytes]) -> None:
    with ZipFile(path, "w", ZIP_DEFLATED) as zf:
        for name, data in images.items():
            zf.writestr(name, data)


def test_parse_ids_csv() -> None:
    result = _parse_ids(ids_str="a.cbz:page_001.png,b.cbz:page_002.jpg")
    assert result == {"a.cbz": {"page_001.png"}, "b.cbz": {"page_002.jpg"}}


def test_parse_ids_file(tmp_path: Path) -> None:
    f = tmp_path / "ids.txt"
    f.write_text("a.cbz:page_001.png\nb.cbz:page_002.jpg\n")
    result = _parse_ids(ids_file=str(f))
    assert result == {"a.cbz": {"page_001.png"}, "b.cbz": {"page_002.jpg"}}


def test_parse_ids_ignores_comments_and_blanks(tmp_path: Path) -> None:
    f = tmp_path / "ids.txt"
    f.write_text("# comment\n\na.cbz:page_001.png\n")
    result = _parse_ids(ids_file=str(f))
    assert result == {"a.cbz": {"page_001.png"}}


def test_parse_ids_error_no_ids() -> None:
    import pytest
    with pytest.raises(ValueError, match="No IDs provided"):
        _parse_ids()


def test_parse_ids_error_bad_format() -> None:
    import pytest
    with pytest.raises(ValueError, match="missing"):
        _parse_ids(ids_str="badformat")


def test_parse_ids_error_missing_file(tmp_path: Path) -> None:
    import pytest
    with pytest.raises(FileNotFoundError):
        _parse_ids(ids_file=str(tmp_path / "nonexistent.txt"))


def test_delete_ids_from_cbz(tmp_path: Path) -> None:
    pages = {"page_001.png": _make_image_png(10, 10, (255, 0, 0)),
             "page_002.png": _make_image_png(10, 10, (0, 255, 0)),
             "page_003.png": _make_image_png(10, 10, (0, 0, 255))}
    cbz = tmp_path / "test.cbz"
    _write_cbz(cbz, pages)

    changed, removed = _delete_ids_from_cbz(cbz, {"page_002.png"}, delete=True)
    assert changed
    assert removed == 1

    with ZipFile(cbz, "r") as zr:
        names = sorted(zr.namelist())
    assert names == ["page_001.png", "page_002.png"]

    # page_002 (formerly page_003) should be blue
    with ZipFile(cbz, "r") as zr:
        img = Image.open(BytesIO(zr.read("page_002.png")))
    assert img.getpixel((0, 0)) == (0, 0, 255)


def test_delete_ids_from_cbz_no_match(tmp_path: Path) -> None:
    pages = {"page_001.png": _make_image_png(10, 10)}
    cbz = tmp_path / "test.cbz"
    _write_cbz(cbz, pages)

    changed, removed = _delete_ids_from_cbz(cbz, {"page_999.png"}, delete=True)
    assert not changed
    assert removed == 0


def test_delete_ids_backup_mode(tmp_path: Path) -> None:
    pages = {"page_001.png": _make_image_png(10, 10),
             "page_002.png": _make_image_png(10, 10, (0, 255, 0))}
    cbz = tmp_path / "test.cbz"
    _write_cbz(cbz, pages)

    changed, removed = _delete_ids_from_cbz(cbz, {"page_002.png"}, delete=False)
    assert changed
    assert removed == 1

    assert (tmp_path / "test_OLD.cbz").exists()
    with ZipFile(cbz, "r") as zr:
        assert zr.namelist() == ["page_001.png"]


def test_delete_pages_by_id_full_workflow(tmp_path: Path) -> None:
    _write_cbz(tmp_path / "ch01.cbz", {
        "page_001.png": _make_image_png(10, 10, (255, 0, 0)),
        "page_002.png": _make_image_png(10, 10, (0, 255, 0)),
        "page_003.png": _make_image_png(10, 10, (0, 0, 255)),
    })
    _write_cbz(tmp_path / "ch02.cbz", {
        "page_001.png": _make_image_png(10, 10, (255, 255, 0)),
        "page_002.png": _make_image_png(10, 10, (0, 255, 255)),
    })

    ids_file = tmp_path / "to_delete.txt"
    ids_file.write_text("ch01.cbz:page_002.png\nch02.cbz:page_001.png\n")

    rc = delete_pages_by_id(tmp_path, ids_file=str(ids_file), delete=True)
    assert rc == 0

    with ZipFile(tmp_path / "ch01.cbz", "r") as zr:
        assert zr.namelist() == ["page_001.png", "page_002.png"]
    with ZipFile(tmp_path / "ch02.cbz", "r") as zr:
        assert zr.namelist() == ["page_001.png"]
