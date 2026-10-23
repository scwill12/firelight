#!/usr/bin/env python3
"""Draws the App Store creative assets — the product page header and the
search results image.

These are not screenshots. Apple's own guidance separates them: a header
carries "a single, clear idea" for someone who has never seen the app, and a
search results image states the purpose "at a glance" by showing the
interface. So the header is the shelf itself, and the search image is the app
running.

Sizes are the dedicated ones from Apple's creative asset specifications, so
neither image is cropped on the way in:

    header  3840 x 1646   21:9
    search  3840 x 2560   3:2

Both are written as PNG with no alpha channel, which Apple requires.

    python3 scripts/make_creative_assets.py

Requires Pillow, the demo covers, and the raw captures in docs/screenshots.
"""
from __future__ import annotations

import math
import pathlib

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
COVERS = ROOT / "Packages/FirelightKit/Sources/DemoKit/Resources"
RAW = ROOT / "docs/screenshots"
OUT = ROOT / "docs/creative"

# The same ember the listing screenshots use, so the whole store page reads as
# one piece of design rather than three.
TOP = (26, 22, 18)
BOTTOM = (74, 34, 12)
INK = (255, 250, 244)
SUBTLE = (214, 196, 178)
GLOW = (255, 150, 60)

SERIF = "/System/Library/Fonts/Supplemental/Georgia Bold.ttf"
SANS = "/System/Library/Fonts/SFNS.ttf"

# Covers are fanned centre-outwards, so the order here is the order they sit
# in the arc, not the order they are drawn.
#
# Five, not nine. Audiobookshelf covers are square, so a fan of them overlaps
# edge-on rather than spine-on, and anything tighter than this buries the
# titles of everything but the middle card — which reads as a stack of blank
# colour chips. Colours alternate so no two neighbours are the same family.
FAN = [
    "cover-dracula.png",
    "cover-oz.png",
    "cover-alice.png",
    "cover-holmes.png",
    "cover-timemachine.png",
]

# The library grid and the home shelves are dense; the book detail screen is
# mostly white space below the fold, which looks like a half-loaded app at
# this size.
DEVICES = ["02-library.png", "04-player.png", "01-home.png"]


def gradient(width: int, height: int) -> Image.Image:
    """A vertical wash drawn per row, then a warm glow low in the frame."""
    column = Image.new("RGB", (1, height))
    pixels = column.load()
    for y in range(height):
        t = y / (height - 1)
        pixels[0, y] = tuple(round(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3))
    canvas = column.resize((width, height)).convert("RGBA")

    # The glow is what makes it firelight rather than a brown gradient. Drawn
    # small and scaled up, because a per-pixel radial at this size is slow.
    small = 220
    layer = Image.new("L", (small, small), 0)
    draw = ImageDraw.Draw(layer)
    for step in range(small // 2, 0, -1):
        t = 1 - step / (small / 2)
        draw.ellipse(
            [small / 2 - step, small / 2 - step, small / 2 + step, small / 2 + step],
            fill=round(150 * t**2),
        )
    glow_size = round(width * 1.15)
    mask = layer.resize((glow_size, glow_size), Image.LANCZOS)
    tint = Image.new("RGBA", (glow_size, glow_size), GLOW + (0,))
    tint.putalpha(mask)
    canvas.alpha_composite(
        tint, (round((width - glow_size) / 2), round(height - glow_size * 0.58))
    )
    return canvas


def rounded(image: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, *image.size], radius=radius, fill=255)
    out = image.convert("RGBA")
    out.putalpha(mask)
    return out


def shadow(size: tuple[int, int], radius: int, blur: int, spread: int, alpha: int) -> Image.Image:
    layer = Image.new("RGBA", (size[0] + spread * 2, size[1] + spread * 2), (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle(
        [spread, spread, spread + size[0], spread + size[1]],
        radius=radius,
        fill=(0, 0, 0, alpha),
    )
    return layer.filter(ImageFilter.GaussianBlur(blur))


def centred(draw: ImageDraw.ImageDraw, text: str, font, y: int, width: int, fill) -> int:
    left, top, right, bottom = draw.textbbox((0, 0), text, font=font)
    draw.text(((width - (right - left)) / 2 - left, y - top), text, font=font, fill=fill)
    return bottom - top


def header() -> None:
    """The shelf itself: a fanned hand of covers under one short phrase."""
    width, height = 3840, 1646
    canvas = gradient(width, height)

    cover_height = 660
    spacing = 690
    middle = len(FAN) // 2

    # Outside in, so the centre cover finishes on top of its neighbours.
    order = sorted(range(len(FAN)), key=lambda i: -abs(i - middle))
    for index in order:
        distance = index - middle
        scale = 1.0 - 0.06 * abs(distance)
        angle = -6.0 * distance
        size = round(cover_height * scale)

        art = Image.open(COVERS / FAN[index]).convert("RGB")
        art = art.resize((round(size * art.width / art.height), size), Image.LANCZOS)
        art = rounded(art, round(26 * scale))

        # A warm hairline lifts each cover off the one behind it.
        ImageDraw.Draw(art).rounded_rectangle(
            [0, 0, art.width - 1, art.height - 1],
            radius=round(26 * scale),
            outline=(255, 224, 196, 70),
            width=3,
        )

        plate = Image.new("RGBA", (art.width + 120, art.height + 120), (0, 0, 0, 0))
        plate.alpha_composite(
            shadow(art.size, round(26 * scale), 34, 60, 165), (0, 14)
        )
        plate.alpha_composite(art, (60, 60))
        plate = plate.rotate(angle, Image.BICUBIC, expand=True)

        # The arc: covers further from the centre sit lower.
        x = round(width / 2 + distance * spacing - plate.width / 2)
        y = round(1150 - math.cos(distance * 0.52) * 90 - plate.height / 2)
        canvas.alpha_composite(plate, (x, y))

    draw = ImageDraw.Draw(canvas)
    centred(draw, "Your library, lit", ImageFont.truetype(SERIF, 170), 250, width, INK)
    centred(
        draw,
        "Audiobooks, ebooks and comics from your own Audiobookshelf server",
        ImageFont.truetype(SANS, 62),
        492,
        width,
        SUBTLE,
    )

    OUT.mkdir(parents=True, exist_ok=True)
    target = OUT / "header-3840x1646.png"
    canvas.convert("RGB").save(target, "PNG", optimize=True)
    print(f"  {target.relative_to(ROOT)}  3840x1646  21:9")


def search() -> None:
    """The app running, which is what this placement is for."""
    width, height = 3840, 2560
    canvas = gradient(width, height)

    draw = ImageDraw.Draw(canvas)
    centred(draw, "Your shelf, on your server", ImageFont.truetype(SERIF, 150), 230, width, INK)
    centred(
        draw,
        "No accounts, no ads, no tracking",
        ImageFont.truetype(SANS, 58),
        442,
        width,
        SUBTLE,
    )

    tall = 1740
    gap = 108
    plates = []
    for index, name in enumerate(DEVICES):
        scale = 1.0 if index == 1 else 0.9
        shot = Image.open(RAW / name).convert("RGB")
        size = round(tall * scale)
        plate = shot.resize((round(size * shot.width / shot.height), size), Image.LANCZOS)
        plates.append(rounded(plate, round(62 * scale)))

    total = sum(p.width for p in plates) + gap * (len(plates) - 1)
    x = round((width - total) / 2)
    baseline = 2470

    # Outer devices first so the taller middle one overlaps them.
    for index in (0, 2, 1):
        plate = plates[index]
        px = x + sum(p.width for p in plates[:index]) + gap * index
        py = baseline - plate.height
        canvas.alpha_composite(
            shadow(plate.size, 62, 54, 70, 170), (px - 70, py - 70 + 30)
        )
        canvas.alpha_composite(plate, (px, py))
        ImageDraw.Draw(canvas).rounded_rectangle(
            [px, py, px + plate.width, py + plate.height],
            radius=62,
            outline=(255, 255, 255, 46),
            width=3,
        )

    OUT.mkdir(parents=True, exist_ok=True)
    target = OUT / "search-3840x2560.png"
    canvas.convert("RGB").save(target, "PNG", optimize=True)
    print(f"  {target.relative_to(ROOT)}  3840x2560  3:2")


def main() -> None:
    missing = [n for n in FAN if not (COVERS / n).exists()]
    missing += [n for n in DEVICES if not (RAW / n).exists()]
    if missing:
        raise SystemExit("missing source art: " + ", ".join(missing))
    header()
    search()


if __name__ == "__main__":
    main()
