#!/usr/bin/env python3
"""Composes the iPad App Store screenshots from the raw iPad captures.

The iPhone script's companion, and the same visual language — ember wash,
Georgia headline, a rounded plate bleeding off the bottom. It is a separate
file because the geometry is genuinely different: an iPad capture is 3:4
rather than 19.5:9, so the plate cannot simply be the full width with a
headline stacked above it.

The real problem on iPad is empty screen. A nine-book sample library fills
about half of a 13-inch grid, and the rest is white. The iPhone script has a
hand-tuned `trim` per screen for this; here the dead region is measured
instead, because the amount varies per screen and per simulator and a wrong
constant is worse than none.

    python3 scripts/make_ipad_screenshots.py

Reads docs/screenshots-ipad/*.png, writes docs/store-ipad/*.png at
2064 x 2752, which is what IPAD_13_PROFILE wants.

Requires Pillow.
"""
from __future__ import annotations

import pathlib

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
RAW = ROOT / "docs/screenshots-ipad"
OUT = ROOT / "docs/store-ipad"

WIDTH, HEIGHT = 2064, 2752

TOP = (26, 22, 18)
BOTTOM = (74, 34, 12)
INK = (255, 250, 244)
SUBTLE = (214, 196, 178)

SERIF = "/System/Library/Fonts/Supplemental/Georgia Bold.ttf"
SANS = "/System/Library/Fonts/SFNS.ttf"

CAPTIONS = [
    ("01-home.png", "Your library, wherever you are", "Shelves that work offline"),
    ("02-library.png", "Everything on your own server", "No accounts, no ads, no tracking"),
    ("03-book.png", "Start listening in one tap", "Play or read, from the same screen"),
    ("04-player.png", "Chapters, speed, and a sleep timer", "Built for long books"),
    ("05-chapters.png", "Never lose your place", "Positions sync both ways"),
]


def gradient() -> Image.Image:
    column = Image.new("RGB", (1, HEIGHT))
    pixels = column.load()
    for y in range(HEIGHT):
        t = y / (HEIGHT - 1)
        pixels[0, y] = tuple(round(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3))
    return column.resize((WIDTH, HEIGHT))


def rounded(image: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, *image.size], radius=radius, fill=255)
    out = image.convert("RGBA")
    out.putalpha(mask)
    return out


def shadow(size: tuple[int, int], radius: int, blur: int, spread: int) -> Image.Image:
    layer = Image.new("RGBA", (size[0] + spread * 2, size[1] + spread * 2), (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle(
        [spread, spread, spread + size[0], spread + size[1]], radius=radius, fill=(0, 0, 0, 150)
    )
    return layer.filter(ImageFilter.GaussianBlur(blur))


def dead_rows(image: Image.Image, tolerance: int = 6) -> int:
    """How many identical rows the capture ends with.

    Measured rather than guessed: a row of empty screen is pixel-identical to
    the row above it, whatever colours the sidebar and content area happen to
    be. Comparing each row to the final row finds the run without caring about
    the layout. A screen that genuinely fills the display returns 0.
    """
    # The last rows carry the home indicator and the scroll indicator, so they
    # are not representative of empty screen. Reference a row above them.
    floor = 120
    small = image.convert("RGB").resize((160, image.height), Image.BILINEAR)
    pixels = small.load()
    reference_y = image.height - 1 - floor
    last = [pixels[x, reference_y] for x in range(160)]
    count = floor
    for y in range(reference_y, -1, -1):
        row = [pixels[x, y] for x in range(160)]
        if max(abs(a[i] - b[i]) for a, b in zip(row, last) for i in range(3)) > tolerance:
            break
        count += 1
    return 0 if count <= floor else count


def wrap(draw: ImageDraw.ImageDraw, text: str, font, limit: int) -> list[str]:
    words, lines, current = text.split(), [], ""
    for word in words:
        trial = f"{current} {word}".strip()
        if draw.textlength(trial, font=font) <= limit or not current:
            current = trial
        else:
            lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def compose(source: pathlib.Path, headline: str, sub: str, target: pathlib.Path) -> None:
    canvas = gradient().convert("RGBA")
    draw = ImageDraw.Draw(canvas)

    headline_font = ImageFont.truetype(SERIF, 132)
    sub_font = ImageFont.truetype(SANS, 60)

    margin = 150
    y = 210
    for line in wrap(draw, headline, headline_font, WIDTH - margin * 2):
        draw.text((margin, y), line, font=headline_font, fill=INK)
        y += 158
    draw.text((margin, y + 24), sub, font=sub_font, fill=SUBTLE)

    shot = Image.open(source).convert("RGB")
    plate_width = WIDTH - margin * 2
    plate_y = y + 190
    scale = plate_width / shot.width

    # Two constraints, and the tighter one wins. The plate should reach the
    # bottom edge so the screen reads as continuing past the frame, which caps
    # how much source height is wanted; and the crop must not eat into real
    # content, which caps how much may be removed. Trimming to the measured
    # dead space alone leaves a short plate floating in the gradient.
    wanted = round((HEIGHT - plate_y) / scale)
    allowed = max(dead_rows(shot) - 40, 0)
    cut = max(min(allowed, shot.height - wanted), 0)
    if cut:
        shot = shot.crop((0, 0, shot.width, shot.height - cut))

    plate = rounded(shot.resize((plate_width, round(shot.height * scale)), Image.LANCZOS), 44)
    canvas.alpha_composite(shadow(plate.size, 44, 54, 70), (margin - 70, plate_y - 70 + 28))
    canvas.alpha_composite(plate, (margin, plate_y))
    ImageDraw.Draw(canvas).rounded_rectangle(
        [margin, plate_y, margin + plate.width, plate_y + plate.height],
        radius=44, outline=(255, 255, 255, 38), width=3,
    )

    canvas.convert("RGB").save(target, "PNG", optimize=True)
    print(f"  {target.name}  trimmed {cut}px of empty screen")


def main() -> None:
    if not RAW.is_dir():
        raise SystemExit(f"No captures at {RAW}")
    OUT.mkdir(parents=True, exist_ok=True)
    for name, headline, sub in CAPTIONS:
        source = RAW / name
        if not source.exists():
            print(f"  missing {name} — skipped")
            continue
        compose(source, headline, sub, OUT / name)


if __name__ == "__main__":
    main()
