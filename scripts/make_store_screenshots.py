#!/usr/bin/env python3
"""Composes App Store marketing screenshots from the raw captures.

`FirelightScreenshots` photographs the app; this frames those captures on a
branded background with a headline, which is what an App Store listing
actually wants. Raw simulator captures are accurate and dull — they sell
nothing, and the listing is the only thing most people see.

Reads `docs/screenshots/*.png`, writes `docs/store/*.png` at the same
1320 × 2868 that App Store Connect requires for 6.9".

    python3 scripts/make_store_screenshots.py

Requires Pillow.
"""
from __future__ import annotations

import pathlib

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
RAW = ROOT / "docs/screenshots"
OUT = ROOT / "docs/store"

WIDTH, HEIGHT = 1320, 2868

# Firelight's ember, dark enough that white type sits on it comfortably.
TOP = (26, 22, 18)
BOTTOM = (74, 34, 12)
INK = (255, 250, 244)
SUBTLE = (214, 196, 178)

SERIF = "/System/Library/Fonts/Supplemental/Georgia Bold.ttf"
SANS = "/System/Library/Fonts/SFNS.ttf"

# One claim per screen, in the app's own voice: plain, no exclamation marks.
#
# `trim` is how many pixels of empty screen to cut from the bottom of the
# capture before framing it. Several screens end in whitespace, which is fine
# in the app and dead weight in a listing — the plate bleeds off the frame
# anyway, so the cut is invisible.
CAPTIONS = [
    ("01-home.png", "Your library,\nwherever you are", "Shelves that work offline", 0),
    ("02-library.png", "Everything on\nyour own server", "No accounts, no ads, no tracking", 380),
    ("03-book.png", "Start listening\nin one tap", "Play or read, from the same screen", 0),
    ("04-player.png", "Chapters, speed,\nand a sleep timer", "Built for long books", 720),
    ("05-chapters.png", "Never lose\nyour place", "Positions sync both ways", 0),
]


def gradient() -> Image.Image:
    """A vertical wash, drawn per row so there is no banding."""
    background = Image.new("RGB", (1, HEIGHT))
    pixels = background.load()
    for y in range(HEIGHT):
        t = y / (HEIGHT - 1)
        pixels[0, y] = tuple(
            round(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)
        )
    return background.resize((WIDTH, HEIGHT))


def rounded(image: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, *image.size], radius=radius, fill=255)
    out = image.convert("RGBA")
    out.putalpha(mask)
    return out


def shadow(size: tuple[int, int], radius: int, blur: int, spread: int) -> Image.Image:
    """A soft drop shadow for the device plate."""
    layer = Image.new("RGBA", (size[0] + spread * 2, size[1] + spread * 2), (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle(
        [spread, spread, spread + size[0], spread + size[1]],
        radius=radius,
        fill=(0, 0, 0, 150),
    )
    return layer.filter(ImageFilter.GaussianBlur(blur))


def wrap_lines(text: str) -> list[str]:
    return [line.strip() for line in text.split("\n")]


def compose(
    source: pathlib.Path, headline: str, sub: str, trim: int, target: pathlib.Path
) -> None:
    canvas = gradient().convert("RGBA")
    draw = ImageDraw.Draw(canvas)

    headline_font = ImageFont.truetype(SERIF, 104)
    sub_font = ImageFont.truetype(SANS, 48)

    # Headline block, top-aligned with generous air above it.
    y = 190
    for line in wrap_lines(headline):
        draw.text((96, y), line, font=headline_font, fill=INK)
        y += 124
    draw.text((96, y + 18), sub, font=sub_font, fill=SUBTLE)

    # The capture, scaled to leave margins, and bled off the bottom edge so
    # the screen reads as continuing past the frame.
    shot = Image.open(source).convert("RGB")
    if trim:
        shot = shot.crop((0, 0, shot.width, shot.height - trim))
    plate_width = WIDTH - 192
    scale = plate_width / shot.width
    plate = shot.resize((plate_width, round(shot.height * scale)), Image.LANCZOS)
    plate = rounded(plate, 56)

    plate_x = 96
    plate_y = y + 150

    glow = shadow(plate.size, 56, 48, 60)
    canvas.alpha_composite(glow, (plate_x - 60, plate_y - 60 + 24))
    canvas.alpha_composite(plate, (plate_x, plate_y))

    # A hairline, so the plate separates from the background on dark screens.
    ImageDraw.Draw(canvas).rounded_rectangle(
        [plate_x, plate_y, plate_x + plate.width, plate_y + plate.height],
        radius=56,
        outline=(255, 255, 255, 38),
        width=2,
    )

    canvas.convert("RGB").save(target, "PNG", optimize=True)


def main() -> None:
    if not RAW.is_dir():
        raise SystemExit(f"No captures at {RAW}. Run the FirelightScreenshots scheme first.")
    OUT.mkdir(parents=True, exist_ok=True)

    written = 0
    for name, headline, sub, trim in CAPTIONS:
        source = RAW / name
        if not source.exists():
            print(f"  missing {name} — skipped")
            continue
        target = OUT / name
        compose(source, headline, sub, trim, target)
        print(f"  {target.relative_to(ROOT)}")
        written += 1

    if not written:
        raise SystemExit("Nothing composed; no captures matched.")
    size = sum(f.stat().st_size for f in OUT.iterdir()) / 1_048_576
    print(f"\n{written} marketing screenshots, {WIDTH}x{HEIGHT}, {size:.1f} MB.")


if __name__ == "__main__":
    main()
