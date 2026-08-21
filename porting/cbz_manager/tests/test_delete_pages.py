"""Tests for delete-pages operation."""

from __future__ import annotations

from io import BytesIO
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

from PIL import Image

from cbz_manager.delete_pages import _delete_pages_from_cbz, _parse_pages, delete_pages


def _make_image_png(width: int = 100, height: int = 100, color: tuple[int, int, int] = (255, 0, 0)) -> bytes:
    img = Image.new("RGB", (width, height), color)
    buf = BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def _write_cbz(path: Path, images: dict[str, bytes]) -> None:
    with ZipFile(path, "w", ZIP_DEFLATED) as zf:
        for name, data in images.items():
            zf.writestr(name, data)


def test_parse_pages_single() -> None:
    assert _parse_pages("3") == {3}


def test_parse_pages_range() -> None:
    assert _parse_pages("5-20") == set(range(5, 21))


def test_parse_pages_comma() -> None:
    assert _parse_pages("3,5-7,22") == {3, 5, 6, 7, 22}


def test_parse_pages_invalid() -> None:
    import pytest
    with pytest.raises(ValueError):
        _parse_pages("abc")


def test_parse_pages_range_reversed() -> None:
    import pytest
    with pytest.raises(ValueError, match="start > end"):
        _parse_pages("20-5")


def test_delete_pages_removes_and_renumbers(tmp_path: Path) -> None:
    pages = {"page_001.png": _make_image_png(10, 10, (255, 0, 0)),
             "page_002.png": _make_image_png(10, 10, (0, 255, 0)),
             "page_003.png": _make_image_png(10, 10, (0, 0, 255))}
    cbz = tmp_path / "test.cbz"
    _write_cbz(cbz, pages)

    changed, removed = _delete_pages_from_cbz(cbz, {2}, delete=True)
    assert changed
    assert removed == 1

    with ZipFile(cbz, "r") as zr:
        names = sorted(zr.namelist())
    assert names == ["page_001.png", "page_002.png"]

    # page_002 (formerly page_003) should be blue
    with ZipFile(cbz, "r") as zr:
        img2 = Image.open(BytesIO(zr.read("page_002.png")))
    assert img2.getpixel((0, 0)) == (0, 0, 255)


def test_delete_pages_removes_multiple(tmp_path: Path) -> None:
    pages = {f"page_{i:03d}.png": _make_image_png(10, 10) for i in range(1, 11)}
    cbz = tmp_path / "test.cbz"
    _write_cbz(cbz, pages)

    changed, removed = _delete_pages_from_cbz(cbz, {2, 5, 7}, delete=True)
    assert changed
    assert removed == 3

    with ZipFile(cbz, "r") as zr:
        names = sorted(zr.namelist())
    assert len(names) == 7  # 10 - 3
    assert names == [f"page_{i:03d}.png" for i in range(1, 8)]


def test_delete_pages_no_match(tmp_path: Path) -> None:
    pages = {"page_001.png": _make_image_png(10, 10)}
    cbz = tmp_path / "test.cbz"
    _write_cbz(cbz, pages)

    changed, removed = _delete_pages_from_cbz(cbz, {99}, delete=True)
    assert not changed
    assert removed == 0


def test_delete_pages_filters_comicinfo(tmp_path: Path) -> None:
    with ZipFile(tmp_path / "test.cbz", "w") as zf:
        zf.writestr("ComicInfo.xml", "<xml/>")
        zf.writestr("page_001.png", _make_image_png(10, 10))
        zf.writestr("page_002.png", _make_image_png(10, 10, (0, 255, 0)))

    changed, removed = _delete_pages_from_cbz(
        tmp_path / "test.cbz", {1}, delete=True
    )
    assert changed
    assert removed == 1

    with ZipFile(tmp_path / "test.cbz", "r") as zr:
        names = zr.namelist()
    assert "ComicInfo.xml" not in names
    assert names == ["page_001.png"]


def test_delete_pages_backup_mode(tmp_path: Path) -> None:
    pages = {"page_001.png": _make_image_png(10, 10),
             "page_002.png": _make_image_png(10, 10, (0, 255, 0))}
    cbz = tmp_path / "test.cbz"
    _write_cbz(cbz, pages)

    changed, removed = _delete_pages_from_cbz(cbz, {1}, delete=False)
    assert changed
    assert removed == 1

    assert Path(tmp_path / "test_OLD.cbz").exists()
    assert cbz.exists()

    with ZipFile(cbz, "r") as zr:
        assert zr.namelist() == ["page_001.png"]


def test_delete_pages_in_directory(tmp_path: Path) -> None:
    for i in range(1, 4):
        pages = {f"page_{j:03d}.png": _make_image_png(10, 10) for j in range(1, 6)}
        _write_cbz(tmp_path / f"ch_{i:04d}.cbz", pages)

    rc = delete_pages(tmp_path, "2,4", delete=True)
    assert rc == 0

    for cbz in sorted(tmp_path.glob("*.cbz")):
        with ZipFile(cbz, "r") as zr:
            names = zr.namelist()
        assert len(names) == 3  # 5 - 2
        assert names == [f"page_{i:03d}.png" for i in range(1, 4)]


def test_delete_pages_no_cbz(tmp_path: Path, capsys) -> None:
    rc = delete_pages(tmp_path, "3", delete=True)
    assert rc == 0
    captured = capsys.readouterr()
    assert "No .cbz files" in captured.out
