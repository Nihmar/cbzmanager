"""Tests for find-similar operation."""

from __future__ import annotations

from io import BytesIO
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

from PIL import Image

from cbz_manager.find_similar import _dhash, _hamming, _group_similar, _sanitize, find_similar


def _make_image_png(width: int = 100, height: int = 100, color: tuple[int, int, int] = (255, 0, 0)) -> bytes:
    img = Image.new("RGB", (width, height), color)
    buf = BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def _make_checkerboard(size: int = 64, tile: int = 8) -> bytes:
    """Create a checkerboard pattern image."""
    img = Image.new("RGB", (size, size))
    for y in range(size):
        for x in range(size):
            if ((x // tile) + (y // tile)) % 2 == 0:
                img.putpixel((x, y), (255, 255, 255))
            else:
                img.putpixel((x, y), (0, 0, 0))
    buf = BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def _make_bars(size: int = 64, bar_width: int = 16) -> bytes:
    """Create a vertical bar pattern image."""
    img = Image.new("RGB", (size, size))
    for y in range(size):
        for x in range(size):
            if (x // bar_width) % 2 == 0:
                img.putpixel((x, y), (255, 255, 255))
            else:
                img.putpixel((x, y), (0, 0, 0))
    buf = BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def _write_cbz(path: Path, images: dict[str, bytes]) -> None:
    with ZipFile(path, "w", ZIP_DEFLATED) as zf:
        for name, data in images.items():
            zf.writestr(name, data)


def test_dhash_identical_images_have_same_hash() -> None:
    data = _make_checkerboard(64, 8)
    img_a = Image.open(BytesIO(data))
    img_b = Image.open(BytesIO(data))
    assert _dhash(img_a) == _dhash(img_b)


def test_dhash_different_images_have_different_hashes() -> None:
    img_a = Image.open(BytesIO(_make_checkerboard(64, 8)))
    img_b = Image.open(BytesIO(_make_bars(64, 16)))
    assert _dhash(img_a) != _dhash(img_b)


def test_hamming_zero_for_same() -> None:
    h = _dhash(Image.open(BytesIO(_make_image_png(50, 50, (128, 128, 128)))))
    assert _hamming(h, h) == 0


def test_hamming_max_for_opposites() -> None:
    a = 0x0
    b = 0xFFFFFFFFFFFFFFFF
    assert _hamming(a, b) == 64


def test_group_similar_no_groups() -> None:
    entries: list = []
    assert _group_similar(entries, 10) == []


def test_group_similar_two_similar() -> None:
    cb_data = _make_checkerboard(64, 8)
    bars_data = _make_bars(64, 16)

    img_cb = Image.open(BytesIO(cb_data))
    img_bars = Image.open(BytesIO(bars_data))

    hash_cb = _dhash(img_cb)
    hash_bars = _dhash(img_bars)

    entries = [
        ("a.cbz", "page_001.png", hash_cb, cb_data),
        ("b.cbz", "page_002.png", hash_cb, cb_data),
        ("c.cbz", "page_003.png", hash_bars, bars_data),
    ]

    groups = _group_similar(entries, 10)
    assert len(groups) == 1
    assert len(groups[0]) == 2


def test_sanitize_replaces_bad_chars() -> None:
    assert _sanitize("a/b:c d") == "a_b_c_d"


def test_find_similar_creates_groups(tmp_path: Path) -> None:
    cb_data = _make_checkerboard(64, 8)
    bars_data = _make_bars(64, 16)

    _write_cbz(tmp_path / "ch01.cbz", {"page_001.png": cb_data,
                                        "page_002.png": bars_data,
                                        "page_003.png": cb_data})
    _write_cbz(tmp_path / "ch02.cbz", {"page_001.png": cb_data,
                                        "page_002.png": bars_data})

    out = tmp_path / "similar"
    rc = find_similar(tmp_path, out, threshold=10)
    assert rc == 0

    all_ids = set()
    for g in sorted(out.iterdir()):
        if g.is_dir() and (g / "ids.txt").exists():
            for line in g.joinpath("ids.txt").read_text().splitlines():
                if line.strip():
                    all_ids.add(line.strip())

    assert "ch01.cbz:page_001.png" in all_ids
    assert "ch01.cbz:page_003.png" in all_ids
    assert "ch02.cbz:page_001.png" in all_ids


def test_find_similar_no_cbz(tmp_path: Path, capsys) -> None:
    rc = find_similar(tmp_path, tmp_path / "out", threshold=10)
    assert rc == 0
    captured = capsys.readouterr()
    assert "No .cbz files" in captured.out
