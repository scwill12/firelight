#!/usr/bin/env python3
"""Renders Firelight's app icon.

Kept as a script so the icon is reproducible and tweakable, rather than a
binary with no source. Pure standard library: no Pillow, no build dependency.

    python3 scripts/make_app_icon.py
"""
from __future__ import annotations

import math
import pathlib
import struct
import zlib

SIZE = 1024
ROOT = pathlib.Path(__file__).resolve().parent.parent

# Alternate icons are the same flame at different temperatures. `tint` is a
# full RGB multiplier: scaling blue alone cannot make a cool flame, because
# red dominates the base colours.
VARIANTS = {
    "AppIcon": {"tint": (1.00, 1.00, 1.00), "targets": [
        "App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png",
        "Watch/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png",
    ]},
    "AppIcon-Hearth": {"tint": (1.00, 0.58, 0.45), "targets": [
        "App/Resources/Assets.xcassets/AppIcon-Hearth.appiconset/AppIcon-1024.png",
    ]},
    "AppIcon-Moonlight": {"tint": (0.50, 0.88, 2.90), "targets": [
        "App/Resources/Assets.xcassets/AppIcon-Moonlight.appiconset/AppIcon-1024.png",
    ]},
}

# Set per render by main().
TINT = (1.0, 1.0, 1.0)

# Flame geometry, in normalised coordinates with the origin at the icon centre,
# y increasing downwards. A flame is not a teardrop: it is widest around two
# thirds of the way down, narrows into a rounded base, and leans at the tip.
TIP_Y = -0.74
BASE_Y = 0.49
BASE_CENTRE_Y = 0.33
BASE_RADIUS = 0.200
MAX_HALF_WIDTH = 0.325
# sin(pi * t**WIDTH_POWER) peaks at t = 0.5 ** (1 / WIDTH_POWER); at 1.8 that
# puts the widest point about two thirds of the way down, which is what makes
# the shape read as a flame rather than a bulb or a droplet.
WIDTH_POWER = 1.8
CORE_SCALE = 0.50


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def smoothstep(edge0: float, edge1: float, x: float) -> float:
    if edge1 == edge0:
        return 0.0
    t = min(max((x - edge0) / (edge1 - edge0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def smooth_min(a: float, b: float, k: float = 0.22) -> float:
    """Polynomial smooth minimum, so the body and the rounded base merge into
    one silhouette instead of meeting at a visible seam."""
    h = min(max(0.5 + 0.5 * (b - a) / k, 0.0), 1.0)
    return b * (1 - h) + a * h - k * h * (1 - h)


def half_width(t: float) -> float:
    """Flame half-width at height `t`, 0 at the tip and 1 at the base."""
    if t <= 0 or t >= 1:
        return 0.0
    return MAX_HALF_WIDTH * math.sin(math.pi * t**WIDTH_POWER) ** 0.75


def centre_x(t: float) -> float:
    """A gentle lean, so the tip licks rather than points straight up."""
    return 0.06 * math.sin(math.pi * t) * (1 - t) ** 0.5


def flame_distance(x: float, y: float) -> float:
    """<= 1 is inside the flame, > 1 is outside. 1.0 is the edge."""
    t = (y - TIP_Y) / (BASE_Y - TIP_Y)
    body = 10.0
    width = half_width(t)
    if 0 < t < 1 and width > 1e-6:
        body = abs(x - centre_x(t)) / width
    # Round the base rather than letting the body taper to a point.
    base = math.hypot(x - centre_x(1.0), y - BASE_CENTRE_Y) / BASE_RADIUS
    return smooth_min(body, base)


def core_distance(x: float, y: float) -> float:
    """The same flame, shrunk about the base, for the hot inner core."""
    anchor = BASE_CENTRE_Y + 0.04
    return flame_distance(x / CORE_SCALE, (y - anchor) / CORE_SCALE + anchor)


def pixel(x: float, y: float) -> tuple[int, int, int]:
    # Background: a near-black page, slightly warmer at the top.
    vertical = (y + 1) / 2
    r = lerp(0.105, 0.043, vertical)
    g = lerp(0.082, 0.039, vertical)
    b = lerp(0.094, 0.047, vertical)

    # Ember glow behind the flame, centred on its belly.
    glow_distance = math.hypot(x, y - 0.14)
    glow = max(0.0, 1.0 - glow_distance / 0.92) ** 2.6
    r += glow * 0.50 * TINT[0]
    g += glow * 0.21 * TINT[1]
    b += glow * 0.05 * TINT[2]

    # The flame itself, anti-aliased at the edge.
    distance = flame_distance(x, y)
    coverage = 1.0 - smoothstep(0.985, 1.015, distance)
    if coverage > 0:
        # Cooler orange at the base, brighter amber towards the tip.
        height = min(max((BASE_Y - y) / (BASE_Y - TIP_Y), 0.0), 1.0)
        fr = min(1.0, 1.0 * TINT[0])
        fg = min(1.0, lerp(0.33, 0.80, height**0.85) * TINT[1])
        fb = min(1.0, lerp(0.06, 0.34, height**1.2) * TINT[2])
        r = lerp(r, fr, coverage)
        g = lerp(g, fg, coverage)
        b = lerp(b, fb, coverage)

        # The hot core, soft-edged so it glows rather than stencils.
        core = 1.0 - smoothstep(0.70, 1.05, core_distance(x, y))
        if core > 0:
            r = lerp(r, min(1.0, 1.00 * max(TINT[0], 0.75)), core)
            g = lerp(g, min(1.0, 0.95 * max(TINT[1], 0.80)), core)
            b = lerp(b, min(1.0, 0.78 * max(TINT[2], 0.80)), core * 0.95)

    # Vignette, so the icon has a centre at small sizes.
    vignette = 1.0 - 0.22 * min(1.0, math.hypot(x, y) / 1.25) ** 2
    r, g, b = r * vignette, g * vignette, b * vignette

    def channel(value: float) -> int:
        return max(0, min(255, int(round(value * 255))))

    return channel(r), channel(g), channel(b)


def render() -> bytes:
    rows = bytearray()
    for row in range(SIZE):
        y = (row + 0.5) / SIZE * 2 - 1
        rows.append(0)  # PNG filter type: none
        for column in range(SIZE):
            x = (column + 0.5) / SIZE * 2 - 1
            rows.extend(pixel(x, y))
    return bytes(rows)


def write_png(path: pathlib.Path, raw: bytes) -> None:
    def chunk(tag: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + tag
            + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
        )

    header = struct.pack(">2I5B", SIZE, SIZE, 8, 2, 0, 0, 0)  # 8-bit RGB
    data = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


CONTENTS = """{
  "images" : [
    {
      "filename" : "AppIcon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""


def main() -> None:
    global TINT
    for name, variant in VARIANTS.items():
        TINT = variant["tint"]
        raw = render()
        for relative in variant["targets"]:
            target = ROOT / relative
            write_png(target, raw)
            # Every alternate icon needs its own Contents.json.
            if name != "AppIcon":
                (target.parent / "Contents.json").write_text(CONTENTS)
            print(f"wrote {relative} ({target.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
