"""Pytest fixtures: generates test CBZ files dynamically for each test."""

from __future__ import annotations

import shutil
import zipfile
from io import BytesIO
from pathlib import Path
from zipfile import ZipFile

import pytest
from PIL import Image

TEST_DATA_DIR = Path(__file__).parent / "test_data"


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


def _write_cbz(path: Path, images: dict[str, bytes]) -> None:
    with ZipFile(path, "w", zipfile.ZIP_DEFLATED) as zf:
        for name, data in images.items():
            zf.writestr(name, data)


def _write_empty_cbz(path: Path) -> None:
    with ZipFile(path, "w") as zf:
        pass


def _write_corrupted_cbz(path: Path) -> None:
    with ZipFile(path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("page001.png", b"\x89PNG\r\n\x1a\n" + b"\x00" * 200)
        zf.writestr("page002.png", _make_image_png(50, 50))


def _write_text_cbz(path: Path) -> None:
    with ZipFile(path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("info.txt", "This is not an image")
        zf.writestr("readme.txt", "Just text files here")


def _clean_generate(dirname: str, gen_fn) -> Path:
    d = TEST_DATA_DIR / dirname
    if d.exists():
        shutil.rmtree(d)
    d.mkdir(parents=True, exist_ok=True)
    gen_fn(d)
    return d


# ── Generators ──────────────────────────────────────────────────────


def _gen_validate(d: Path) -> None:
    _write_cbz(d / "valid.cbz", {
        "page001.png": _make_image_png(100, 100, (255, 0, 0)),
        "page002.png": _make_image_png(100, 100, (0, 255, 0)),
        "page003.png": _make_image_png(100, 100, (0, 0, 255)),
    })
    _write_empty_cbz(d / "empty.cbz")
    _write_corrupted_cbz(d / "corrupted.cbz")
    _write_text_cbz(d / "non_image.cbz")


def _gen_convert(d: Path) -> None:
    _write_cbz(d / "large.cbz", {
        "page001.png": _make_image_png(800, 800, (255, 0, 0)),
        "page002.png": _make_image_png(800, 800, (0, 255, 0)),
        "page003.png": _make_image_png(800, 800, (0, 0, 255)),
    })
    webp_buf = BytesIO()
    img = Image.new("RGB", (50, 50), (100, 100, 100))
    img.save(webp_buf, format="WEBP", quality=75, method=6)
    _write_cbz(d / "already_webp.cbz", {"page001.webp": webp_buf.getvalue()})
    _write_cbz(d / "mixed.cbz", {
        "page001.png": _make_image_png(400, 400, (255, 128, 0)),
        "page002.jpg": _make_image_jpg(400, 400, quality=90),
        "page003.png": _make_image_png(400, 400, (128, 0, 255)),
    })


def _gen_merge_basic(d: Path) -> None:
    series = "MyManga"
    img = _make_image_png(50, 50, (200, 100, 50))
    for i in range(7, 13):
        _write_cbz(d / f"{series} - {i:04d}.cbz", {f"page{i:03d}.png": img})
    # Add ComicInfo.xml to first chapter for filtering test
    with ZipFile(d / f"{series} - 0007.cbz", "a", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("ComicInfo.xml", "<ComicInfo></ComicInfo>")
    _write_cbz(d / f"{series} V001.cbz", {"p1.png": img, "p2.png": img, "p3.png": img})
    _write_cbz(d / f"{series} V002.cbz", {"p1.png": img, "p2.png": img, "p3.png": img})


def _gen_merge_insufficient(d: Path) -> None:
    """Lowest chapter = 21, volumes = 10 → CPV = 20/10 = 2. 1 chapter < 2 → skip."""
    series = "ShortManga"
    img = _make_image_png(50, 50, (100, 200, 50))
    _write_cbz(d / f"{series} - 0021.cbz", {"page001.png": img})
    for i in range(1, 11):
        _write_cbz(d / f"{series} V{i:03d}.cbz", {"p1.png": img, "p2.png": img})


def _gen_merge_force(d: Path) -> None:
    """7 chapters with lowest=8, 2 volumes → CPV = 7/2 = 3.5 → 2 vols + 1 remaining."""
    series = "MyManga"
    img = _make_image_png(50, 50, (200, 100, 50))
    for i in range(8, 15):
        _write_cbz(d / f"{series} - {i:04d}.cbz", {f"page{i:03d}.png": img})
    _write_cbz(d / f"{series} V001.cbz", {"p1.png": img, "p2.png": img, "p3.png": img})
    _write_cbz(d / f"{series} V002.cbz", {"p1.png": img, "p2.png": img, "p3.png": img})


def _gen_merge_no_volumes(d: Path) -> None:
    """14 chapters, no volumes → default CPV = 7 → 2 volumes."""
    series = "MyManga"
    img = _make_image_png(50, 50, (200, 100, 50))
    for i in range(1, 15):
        _write_cbz(d / f"{series} - {i:04d}.cbz", {f"page{i:03d}.png": img})


def _gen_merge_special(d: Path) -> None:
    """Chapters 1-3 + SP01 + SP02 → specials treated as chapters 4 and 5."""
    series = "MyManga"
    img = _make_image_png(50, 50, (200, 100, 50))
    for i in range(1, 4):
        _write_cbz(d / f"{series} - {i:04d}.cbz", {f"page{i:03d}.png": img})
    _write_cbz(d / f"{series} - SP01.cbz", {"page_sp01.png": img})
    _write_cbz(d / f"{series} - SP02.cbz", {"page_sp02.png": img})


# ── Fixtures ─────────────────────────────────────────────────────────


@pytest.fixture()
def validate_dir() -> Path:
    return _clean_generate("validate", _gen_validate)


@pytest.fixture()
def convert_dir() -> Path:
    return _clean_generate("convert", _gen_convert)


@pytest.fixture()
def merge_basic_dir() -> Path:
    return _clean_generate("merge_basic", _gen_merge_basic)


@pytest.fixture()
def merge_insufficient_dir() -> Path:
    return _clean_generate("merge_insufficient", _gen_merge_insufficient)


@pytest.fixture()
def merge_force_dir() -> Path:
    return _clean_generate("merge_force", _gen_merge_force)


@pytest.fixture()
def merge_no_volumes_dir() -> Path:
    return _clean_generate("merge_no_volumes", _gen_merge_no_volumes)


@pytest.fixture()
def merge_special_dir() -> Path:
    return _clean_generate("merge_special", _gen_merge_special)
