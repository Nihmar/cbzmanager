"""Generate fixture CBZs with pages in various formats/sizes for the
range-check reproduction probe."""

from __future__ import annotations

import shutil
import zipfile
from io import BytesIO
from pathlib import Path

from PIL import Image

OUT = Path("fixfixtures")


def img_bytes(fmt: str, w: int, h: int, seed: int) -> bytes:
    import random

    rnd = random.Random(seed)
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            px[x, y] = (rnd.randrange(256), rnd.randrange(256), rnd.randrange(256))
    b = BytesIO()
    if fmt == "webp":
        img.save(b, "WEBP", quality=75)
    else:
        img.save(b, fmt.upper())
    return b.getvalue()


def cbz(name: str, pages: list[tuple[str, str, int, int]]) -> None:
    with zipfile.ZipFile(OUT / name, "w", zipfile.ZIP_DEFLATED) as z:
        for i, (ext, fmt, w, h) in enumerate(pages):
            z.writestr(f"page{i+1:03d}.{ext}", img_bytes(fmt, w, h, i + 1))


def main() -> None:
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir()
    cbz("png_even.cbz", [("png", "png", 100, 150)] * 3)
    cbz("png_odd.cbz", [("png", "png", 101, 149), ("png", "png", 33, 17)])
    cbz("jpeg.cbz", [("jpg", "jpeg", 640, 480), ("jpg", "jpeg", 137, 91)])
    cbz("bmp.cbz", [("bmp", "bmp", 320, 200)])
    cbz("webp.cbz", [("webp", "webp", 512, 768), ("webp", "webp", 45, 23)])
    cbz("mixed.cbz", [
        ("png", "png", 200, 100),
        ("jpg", "jpeg", 333, 222),
        ("webp", "webp", 60, 40),
        ("bmp", "bmp", 77, 55),
    ])
    print("fixtures in", OUT)


if __name__ == "__main__":
    main()
