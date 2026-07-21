#!/usr/bin/env python3
"""Genera mipmaps Android e icono Windows desde un PNG fuente."""
from __future__ import annotations

import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("Pillow no disponible; omitiendo generación nativa")
    sys.exit(0)

ROOT = Path(__file__).resolve().parents[1]


def make_square(img: Image.Image, size: int) -> Image.Image:
    img = img.convert("RGBA")
    # Fit into square canvas
    img.thumbnail((size, size), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    x = (size - img.width) // 2
    y = (size - img.height) // 2
    canvas.paste(img, (x, y), img)
    return canvas


def main() -> int:
    if len(sys.argv) < 2:
        print("Uso: apply_app_icon.py <icono.png>")
        return 1
    src = Path(sys.argv[1])
    if not src.exists():
        print(f"No existe: {src}")
        return 1

    base = Image.open(src)
    assets = ROOT / "assets" / "branding"
    assets.mkdir(parents=True, exist_ok=True)
    make_square(base, 1024).save(assets / "app_icon.png")

    # Android mipmaps
    sizes = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    res = ROOT / "android" / "app" / "src" / "main" / "res"
    for folder, size in sizes.items():
        out_dir = res / folder
        out_dir.mkdir(parents=True, exist_ok=True)
        make_square(base, size).save(out_dir / "ic_launcher.png")

    # Windows ICO
    win_dir = ROOT / "windows" / "runner" / "resources"
    win_dir.mkdir(parents=True, exist_ok=True)
    ico_sizes = [16, 32, 48, 64, 128, 256]
    icons = [make_square(base, s) for s in ico_sizes]
    icons[0].save(
        win_dir / "app_icon.ico",
        format="ICO",
        sizes=[(s, s) for s in ico_sizes],
        append_images=icons[1:],
    )
    print("Iconos nativos regenerados")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
