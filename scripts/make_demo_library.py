#!/usr/bin/env python3
"""Builds Firelight's built-in demo library.

A reviewer — or anyone deciding whether to install — can open Firelight with
no Audiobookshelf server and still see a real library. That sample has to be
content we are unambiguously allowed to ship, so everything here is either
public domain or generated on the spot:

  * the text is *Alice's Adventures in Wonderland* (Lewis Carroll, 1865),
  * the narration is synthesised with macOS `say`, so no recording of
    anyone's voice is bundled,
  * the covers are drawn here from nothing.

Kept as a script, like `make_app_icon.py`, so the bundle is reproducible
rather than a pile of binaries with no provenance.

    python3 scripts/make_demo_library.py

Requires macOS (`say`) and Pillow.
"""
from __future__ import annotations

import pathlib
import shutil
import subprocess
import zipfile

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "Packages/FirelightKit/Sources/DemoKit/Resources"

VOICE = "Samantha"

# Public domain: first published 1865.
CHAPTERS = [
    (
        "Down the Rabbit-Hole",
        "Alice was beginning to get very tired of sitting by her sister on the "
        "bank, and of having nothing to do: once or twice she had peeped into "
        "the book her sister was reading, but it had no pictures or "
        "conversations in it, and what is the use of a book, thought Alice, "
        "without pictures or conversations? So she was considering in her own "
        "mind, as well as she could, for the hot day made her feel very sleepy "
        "and stupid, whether the pleasure of making a daisy chain would be "
        "worth the trouble of getting up and picking the daisies, when "
        "suddenly a White Rabbit with pink eyes ran close by her.",
    ),
    (
        "The Pool of Tears",
        "Curiouser and curiouser! cried Alice. She was so much surprised that "
        "for the moment she quite forgot how to speak good English. Now I'm "
        "opening out like the largest telescope that ever was! Goodbye, feet! "
        "And when she looked down at her feet, they seemed to be almost out of "
        "sight, they were getting so far off.",
    ),
    (
        "A Caucus-Race",
        "They were indeed a queer-looking party that assembled on the bank: "
        "the birds with draggled feathers, the animals with their fur clinging "
        "close to them, and all dripping wet, cross, and uncomfortable. The "
        "first question of course was, how to get dry again.",
    ),
]

BOOK_TITLE = "Alice's Adventures in Wonderland"
BOOK_AUTHOR = "Lewis Carroll"


def narrate() -> list[tuple[str, pathlib.Path, float]]:
    """Synthesises one file per chapter and reports each one's length."""
    tracks: list[tuple[str, pathlib.Path, float]] = []
    offset = 0.0
    for index, (title, text) in enumerate(CHAPTERS, start=1):
        path = OUT / f"alice-{index}.m4a"
        subprocess.run(
            ["say", "-v", VOICE, "--data-format=aac", "-o", str(path), text],
            check=True,
        )
        seconds = duration_of(path)
        tracks.append((title, path, seconds))
        print(f"  chapter {index}: {seconds:6.1f}s  {path.name}")
        offset += seconds
    return tracks


def duration_of(path: pathlib.Path) -> float:
    """Reads the real duration back, rather than guessing from the text."""
    out = subprocess.run(
        ["afinfo", str(path)], check=True, capture_output=True, text=True
    ).stdout
    for line in out.splitlines():
        if "estimated duration" in line:
            return float(line.split(":")[1].strip().split()[0])
    raise RuntimeError(f"no duration in afinfo output for {path}")


def cover(path: pathlib.Path, title: str, subtitle: str, hue: tuple[int, int, int]) -> None:
    """Draws a plain, legible cover. Square, to match CoverArt.aspectRatio."""
    size = 600
    image = Image.new("RGB", (size, size), hue)
    draw = ImageDraw.Draw(image)

    # A darker band behind the type so the title reads at thumbnail size. Its
    # top follows the text block for the same reason the text does.
    band_top = size - (len(wrap(title, 16)) * 62 + 52) - size * 0.1
    draw.rectangle([0, band_top, size, size], fill=tuple(int(c * 0.66) for c in hue))

    try:
        title_font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Georgia.ttf", 54)
        small_font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Georgia.ttf", 30)
    except OSError:
        title_font = ImageFont.load_default()
        small_font = ImageFont.load_default()

    # Lay the block out from its own height rather than fixed offsets, or a
    # three-line title runs straight over the author.
    lines = wrap(title, 16)
    line_height = 62
    gap = 18
    block = len(lines) * line_height + gap + 34
    y = size - block - size * 0.06

    for line in lines:
        draw.text((size * 0.08, y), line, font=title_font, fill=(255, 250, 244))
        y += line_height
    draw.text((size * 0.08, y + gap), subtitle, font=small_font, fill=(255, 228, 205))

    image.save(path, "PNG")
    print(f"  cover: {path.name}")


def wrap(text: str, width: int) -> list[str]:
    lines: list[str] = []
    line = ""
    for word in text.split():
        if len(line) + len(word) + 1 > width and line:
            lines.append(line)
            line = word
        else:
            line = f"{line} {word}".strip()
    if line:
        lines.append(line)
    return lines


def epub(path: pathlib.Path) -> None:
    """A minimal but genuinely valid EPUB 3, so Readium opens it for real."""
    chapters = "".join(
        f'<h2>{index}. {title}</h2><p>{text}</p>'
        for index, (title, text) in enumerate(CHAPTERS, start=1)
    )
    body = (
        f"<?xml version='1.0' encoding='utf-8'?>"
        f'<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">'
        f"<head><title>{BOOK_TITLE}</title></head>"
        f"<body><h1>{BOOK_TITLE}</h1><p><i>{BOOK_AUTHOR}</i></p>{chapters}"
        f"<p>This is a short excerpt, included so Firelight has something to "
        f"open before you connect your own server.</p></body></html>"
    )
    nav = (
        "<?xml version='1.0' encoding='utf-8'?>"
        '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">'
        "<head><title>Contents</title></head><body>"
        '<nav epub:type="toc"><ol><li><a href="text.xhtml">Beginning</a></li></ol></nav>'
        "</body></html>"
    )
    opf = (
        "<?xml version='1.0' encoding='utf-8'?>"
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
        f"<dc:identifier id='id'>firelight-demo-alice</dc:identifier>"
        f"<dc:title>{BOOK_TITLE}</dc:title>"
        f"<dc:creator>{BOOK_AUTHOR}</dc:creator>"
        "<dc:language>en</dc:language>"
        "<meta property='dcterms:modified'>2026-01-01T00:00:00Z</meta>"
        "</metadata><manifest>"
        "<item id='nav' href='nav.xhtml' media-type='application/xhtml+xml' properties='nav'/>"
        "<item id='text' href='text.xhtml' media-type='application/xhtml+xml'/>"
        "</manifest><spine><itemref idref='text'/></spine></package>"
    )

    with zipfile.ZipFile(path, "w") as archive:
        # The mimetype entry must be first and stored, not deflated.
        archive.writestr(
            zipfile.ZipInfo("mimetype"), "application/epub+zip", compress_type=zipfile.ZIP_STORED
        )
        archive.writestr(
            "META-INF/container.xml",
            "<?xml version='1.0'?><container version='1.0' "
            "xmlns='urn:oasis:names:tc:opendocument:xmlns:container'><rootfiles>"
            "<rootfile full-path='OEBPS/content.opf' "
            "media-type='application/oebps-package+xml'/></rootfiles></container>",
            compress_type=zipfile.ZIP_DEFLATED,
        )
        archive.writestr("OEBPS/content.opf", opf, compress_type=zipfile.ZIP_DEFLATED)
        archive.writestr("OEBPS/nav.xhtml", nav, compress_type=zipfile.ZIP_DEFLATED)
        archive.writestr("OEBPS/text.xhtml", body, compress_type=zipfile.ZIP_DEFLATED)
    print(f"  ebook: {path.name}")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    print(f"Writing the demo library into {OUT.relative_to(ROOT)}")

    tracks = narrate()
    cover(OUT / "cover-alice.png", BOOK_TITLE, BOOK_AUTHOR, (28, 58, 92))
    cover(OUT / "cover-alice-ebook.png", BOOK_TITLE, f"{BOOK_AUTHOR} · ebook", (92, 38, 28))
    epub(OUT / "alice.epub")

    comic = ROOT / "Tests/Fixtures/sample.cbz"
    if comic.exists():
        shutil.copy(comic, OUT / "sample.cbz")
        cover(OUT / "cover-comic.png", "A Sample Comic", "Firelight", (38, 72, 48))
        print("  comic: sample.cbz")

    # The Swift side needs the real durations; writing them here keeps the
    # bundle and the manifest from drifting apart.
    manifest = "\n".join(
        f"{index}\t{title}\t{seconds:.3f}"
        for index, (title, _, seconds) in enumerate(tracks, start=1)
    )
    (OUT / "alice-chapters.tsv").write_text(manifest + "\n")

    total = sum(seconds for _, _, seconds in tracks)
    size = sum(f.stat().st_size for f in OUT.iterdir()) / 1_048_576
    print(f"\nDone. {total:.0f}s of audio, {size:.1f} MB in the bundle.")


if __name__ == "__main__":
    main()
