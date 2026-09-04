#!/usr/bin/env python3
"""Generate the BioView icon assets in ``assets/`` from the source SVGs.

``favicon.svg`` becomes the app icon, ``favicon_text.svg`` the installer icon.
Requires ``rsvg-convert``; ``.icns`` additionally requires ``iconutil`` (macOS).
Missing optional tools are skipped with a warning.
"""
from __future__ import annotations

import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ASSETS = Path(__file__).resolve().parent.parent / "assets"

# Sizes packed into a Windows .ico (Explorer picks the best fit per context).
ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]
# Sizes an .icns iconset expects (name -> pixel size). iconutil derives the rest.
ICNS_SIZES = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}


def _require(tool: str) -> str:
    path = shutil.which(tool)
    if not path:
        raise SystemExit(f"error: required tool '{tool}' not found on PATH")
    return path


def svg_to_png(svg: Path, out: Path, size: int) -> None:
    """Rasterize an SVG to a square PNG of the given pixel size."""
    rsvg = _require("rsvg-convert")
    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [rsvg, "-w", str(size), "-h", str(size), "-o", str(out), str(svg)],
        check=True,
    )


def build_ico(png_by_size: dict[int, bytes], out: Path) -> None:
    """Pack PNG images into a Windows .ico (each entry stored as PNG, which
    modern Windows supports and keeps the file small for large sizes)."""
    entries = sorted(png_by_size.items())
    count = len(entries)
    header = struct.pack("<HHH", 0, 1, count)  # reserved, type=icon, image count

    offset = 6 + count * 16  # ICONDIR + ICONDIRENTRY table
    dir_entries = b""
    image_data = b""
    for size, png in entries:
        dim = 0 if size >= 256 else size  # 0 means 256 in the ICO spec
        dir_entries += struct.pack(
            "<BBBBHHII",
            dim, dim, 0, 0, 1, 32, len(png), offset,
        )
        image_data += png
        offset += len(png)

    out.write_bytes(header + dir_entries + image_data)


def generate_app_icons(svg: Path) -> None:
    print(f"Generating app icons from {svg.name}")
    svg_to_png(svg, ASSETS / "icon.png", 256)
    svg_to_png(svg, ASSETS / "icon-512.png", 512)

    with tempfile.TemporaryDirectory() as tmp:
        tmpd = Path(tmp)
        png_by_size: dict[int, bytes] = {}
        for size in ICO_SIZES:
            p = tmpd / f"app_{size}.png"
            svg_to_png(svg, p, size)
            png_by_size[size] = p.read_bytes()
        build_ico(png_by_size, ASSETS / "icon.ico")

    _maybe_build_icns(svg, ASSETS / "icon.icns")


def generate_installer_icons(svg: Path) -> None:
    print(f"Generating installer icons from {svg.name}")
    svg_to_png(svg, ASSETS / "installer.png", 256)
    with tempfile.TemporaryDirectory() as tmp:
        tmpd = Path(tmp)
        png_by_size: dict[int, bytes] = {}
        for size in ICO_SIZES:
            p = tmpd / f"inst_{size}.png"
            svg_to_png(svg, p, size)
            png_by_size[size] = p.read_bytes()
        build_ico(png_by_size, ASSETS / "installer.ico")


def _maybe_build_icns(svg: Path, out: Path) -> None:
    iconutil = shutil.which("iconutil")
    if not iconutil:
        print("warning: 'iconutil' not found (macOS only); skipping .icns")
        return
    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "icon.iconset"
        iconset.mkdir()
        for name, size in ICNS_SIZES.items():
            svg_to_png(svg, iconset / name, size)
        subprocess.run(
            [iconutil, "-c", "icns", str(iconset), "-o", str(out)], check=True
        )


def main() -> int:
    app_svg = ASSETS / "favicon.svg"
    installer_svg = ASSETS / "favicon_text.svg"

    if not app_svg.exists() or not installer_svg.exists():
        raise SystemExit(
            f"error: source SVGs not found in {ASSETS} "
            "(expected favicon.svg and favicon_text.svg)"
        )

    generate_app_icons(app_svg)
    generate_installer_icons(installer_svg)
    print(f"Done. Assets written to {ASSETS}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
