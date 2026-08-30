#!/usr/bin/env python3
"""Round the app icon's corners and regenerate every size.

The generated art is a full bleed square. Linux launchers, docks and the app
grid put it next to icons that are rounded squares, so a hard cornered tile
reads as the odd one out.

Radius is 22% of the edge, which is the modern rounded-square convention and
close to what a squircle mask does. That is deliberately much rounder than the
app's own card radius: a 30px corner on a 512px tile would be almost invisible
at 48px, where most of these are actually seen.

The mask is built at 4x and downsampled so the curve is antialiased rather than
stair-stepped, which is very visible at 48px.
"""

import sys
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
MASTER = ROOT / "assets" / "icons" / "app-icon.png"
OUT = ROOT / "assets" / "icons"
BUNDLED = ROOT / "client" / "assets" / "icons"

SIZES = [48, 64, 96, 128, 192, 256, 512]
RADIUS_RATIO = 0.22
SUPERSAMPLE = 4


def rounded_mask(size: int) -> Image.Image:
    big = size * SUPERSAMPLE
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, big - 1, big - 1),
        radius=int(big * RADIUS_RATIO),
        fill=255,
    )
    return mask.resize((size, size), Image.LANCZOS)


def main() -> int:
    if not MASTER.exists():
        print(f"missing {MASTER}", file=sys.stderr)
        return 1

    source = Image.open(MASTER).convert("RGBA")
    BUNDLED.mkdir(parents=True, exist_ok=True)

    for size in SIZES:
        tile = source.resize((size, size), Image.LANCZOS)
        tile.putalpha(rounded_mask(size))
        for target in (OUT / f"app-icon-{size}.png", BUNDLED / f"app-icon-{size}.png"):
            tile.save(target)
        print(f"  app-icon-{size}.png")

    # A rounded master too, so anything generated from it later inherits the
    # shape instead of quietly going square again.
    full = source.copy()
    full.putalpha(rounded_mask(source.width))
    full.save(OUT / "app-icon-rounded.png")
    print("  app-icon-rounded.png (master)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
