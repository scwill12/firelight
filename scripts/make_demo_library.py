#!/usr/bin/env python3
"""Builds Firelight's built-in demo library.

A reviewer — or anyone deciding whether to install — can open Firelight with
no Audiobookshelf server and still see a real library. That sample has to be
content we are unambiguously allowed to ship, so everything here is either
public domain or generated on the spot:

  * the texts are all pre-1929 and long out of copyright,
  * the narration is synthesised with macOS `say`, so no recording of
    anyone's voice is bundled,
  * the covers are drawn here from nothing.

The script also writes `demo-library.json`, which `DemoCatalogue` reads at
runtime. That manifest is the point: durations measured here would otherwise
have to be copied into Swift by hand, and a wrong duration puts every chapter
mark in the wrong place.

    python3 scripts/make_demo_library.py

Requires macOS (`say`, `afinfo`) and Pillow.
"""
from __future__ import annotations

import json
import pathlib
import shutil
import subprocess
from dataclasses import dataclass, field

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "Packages/FirelightKit/Sources/DemoKit/Resources"

VOICE = "Samantha"


@dataclass
class Book:
    slug: str
    title: str
    author: str
    year: str
    hue: tuple[int, int, int]
    blurb: str
    # (chapter title, text to narrate). Empty for a book with no audio.
    chapters: list[tuple[str, str]] = field(default_factory=list)
    # Whether to generate an EPUB from the same text.
    ebook: bool = False


# Every one of these was first published well before 1929.
BOOKS = [
    Book(
        slug="alice",
        title="Alice's Adventures in Wonderland",
        author="Lewis Carroll",
        year="1865",
        hue=(28, 58, 92),
        blurb="A girl follows a waistcoated rabbit underground and finds the world has stopped obeying its own rules.",
        chapters=[
            (
                "Down the Rabbit-Hole",
                "Alice was beginning to get very tired of sitting by her sister on the "
                "bank, and of having nothing to do: once or twice she had peeped into "
                "the book her sister was reading, but it had no pictures or "
                "conversations in it, and what is the use of a book, thought Alice, "
                "without pictures or conversations? So she was considering in her own "
                "mind whether the pleasure of making a daisy chain would be worth the "
                "trouble of getting up and picking the daisies, when suddenly a White "
                "Rabbit with pink eyes ran close by her.",
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
        ],
        ebook=True,
    ),
    Book(
        slug="pride",
        title="Pride and Prejudice",
        author="Jane Austen",
        year="1813",
        hue=(96, 60, 24),
        blurb="Five sisters, a small fortune, and a great deal of being wrong about people.",
        chapters=[
            (
                "A Single Man of Good Fortune",
                "It is a truth universally acknowledged, that a single man in "
                "possession of a good fortune, must be in want of a wife. However "
                "little known the feelings or views of such a man may be on his first "
                "entering a neighbourhood, this truth is so well fixed in the minds of "
                "the surrounding families, that he is considered as the rightful "
                "property of some one or other of their daughters.",
            ),
            (
                "Netherfield Is Taken",
                "My dear Mr. Bennet, said his lady to him one day, have you heard that "
                "Netherfield Park is let at last? Mr. Bennet replied that he had not. "
                "But it is, returned she; for Mrs. Long has just been here, and she "
                "told me all about it.",
            ),
        ],
        ebook=True,
    ),
    Book(
        slug="frankenstein",
        title="Frankenstein",
        author="Mary Shelley",
        year="1818",
        hue=(34, 66, 54),
        blurb="A young scientist makes a living thing, and then will not look after it.",
        chapters=[
            (
                "Letter One",
                "You will rejoice to hear that no disaster has accompanied the "
                "commencement of an enterprise which you have regarded with such evil "
                "forebodings. I arrived here yesterday, and my first task is to assure "
                "my dear sister of my welfare, and increasing confidence in the success "
                "of my undertaking.",
            ),
        ],
        ebook=True,
    ),
    Book(
        slug="holmes",
        title="The Adventures of Sherlock Holmes",
        author="Arthur Conan Doyle",
        year="1892",
        hue=(62, 40, 76),
        blurb="Twelve cases, one impossible lodger, and a narrator who never quite keeps up.",
        chapters=[
            (
                "A Scandal in Bohemia",
                "To Sherlock Holmes she is always the woman. I have seldom heard him "
                "mention her under any other name. In his eyes she eclipses and "
                "predominates the whole of her sex. It was not that he felt any emotion "
                "akin to love for Irene Adler.",
            ),
        ],
    ),
    Book(
        slug="dracula",
        title="Dracula",
        author="Bram Stoker",
        year="1897",
        hue=(88, 26, 30),
        blurb="A solicitor travels east on business and keeps a very careful diary.",
        chapters=[
            (
                "Jonathan Harker's Journal",
                "Left Munich at eight thirty-five at night, arriving at Vienna early "
                "next morning. Buda-Pesth seems a wonderful place, from the glimpse "
                "which I got of it from the train. I feared to go very far from the "
                "station, as we had arrived late and would start as near the correct "
                "time as possible.",
            ),
        ],
        ebook=True,
    ),
    Book(
        slug="timemachine",
        title="The Time Machine",
        author="H. G. Wells",
        year="1895",
        hue=(24, 72, 86),
        blurb="An inventor explains that time is a direction, then demonstrates it.",
        ebook=True,
    ),
    Book(
        slug="mobydick",
        title="Moby-Dick",
        author="Herman Melville",
        year="1851",
        hue=(20, 44, 70),
        blurb="A whaling voyage, a captain with one idea, and a great deal about whales.",
        ebook=True,
    ),
    Book(
        slug="oz",
        title="The Wonderful Wizard of Oz",
        author="L. Frank Baum",
        year="1900",
        hue=(36, 84, 62),
        blurb="A Kansas farmhouse lands somewhere considerably stranger than Kansas.",
        ebook=True,
    ),
]

# Opening lines for the ebook-only titles, so their EPUBs are not empty.
EBOOK_ONLY_TEXT = {
    "timemachine": (
        "The Time Traveller (for so it will be convenient to speak of him) was "
        "expounding a recondite matter to us. His pale grey eyes shone and "
        "twinkled, and his usually pale face was flushed and animated."
    ),
    "mobydick": (
        "Call me Ishmael. Some years ago, never mind how long precisely, having "
        "little or no money in my purse, and nothing particular to interest me on "
        "shore, I thought I would sail about a little and see the watery part of "
        "the world."
    ),
    "oz": (
        "Dorothy lived in the midst of the great Kansas prairies, with Uncle "
        "Henry, who was a farmer, and Aunt Em, who was the farmer's wife. Their "
        "house was small, for the lumber to build it had to be carried by wagon "
        "many miles."
    ),
}


def narrate(book: Book) -> list[dict]:
    """Synthesises one file per chapter and measures each one."""
    tracks: list[dict] = []
    offset = 0.0
    for index, (title, text) in enumerate(book.chapters, start=1):
        resource = f"{book.slug}-{index}"
        path = OUT / f"{resource}.m4a"
        subprocess.run(
            ["say", "-v", VOICE, "--data-format=aac", "-o", str(path), text],
            check=True,
        )
        seconds = duration_of(path)
        tracks.append(
            {"resource": resource, "title": title, "duration": round(seconds, 3),
             "offset": round(offset, 3)}
        )
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

    try:
        title_font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Georgia.ttf", 54)
        small_font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Georgia.ttf", 30)
    except OSError:
        title_font = ImageFont.load_default()
        small_font = ImageFont.load_default()

    lines = wrap(title, 16)
    line_height = 62
    gap = 18

    # A darker band behind the type, sized from the block it has to hold.
    band_top = size - (len(lines) * line_height + 52) - size * 0.1
    draw.rectangle([0, band_top, size, size], fill=tuple(int(c * 0.66) for c in hue))

    y = size - (len(lines) * line_height + gap + 34) - size * 0.06
    for line in lines:
        draw.text((size * 0.08, y), line, font=title_font, fill=(255, 250, 244))
        y += line_height
    draw.text((size * 0.08, y + gap), subtitle, font=small_font, fill=(255, 228, 205))

    image.save(path, "PNG")


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


def epub(path: pathlib.Path, book: Book) -> None:
    """A minimal but genuinely valid EPUB 3, so Readium opens it for real."""
    import zipfile

    if book.chapters:
        sections = "".join(
            f"<h2>{index}. {escape(title)}</h2><p>{escape(text)}</p>"
            for index, (title, text) in enumerate(book.chapters, start=1)
        )
    else:
        sections = f"<p>{escape(EBOOK_ONLY_TEXT.get(book.slug, book.blurb))}</p>"

    body = (
        "<?xml version='1.0' encoding='utf-8'?>"
        '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">'
        f"<head><title>{escape(book.title)}</title></head>"
        f"<body><h1>{escape(book.title)}</h1><p><i>{escape(book.author)}</i></p>{sections}"
        "<p>A short public-domain excerpt, bundled so Firelight has something to "
        "open before you connect your own server.</p></body></html>"
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
        f"<dc:identifier id='id'>firelight-demo-{book.slug}</dc:identifier>"
        f"<dc:title>{escape(book.title)}</dc:title>"
        f"<dc:creator>{escape(book.author)}</dc:creator>"
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
            zipfile.ZipInfo("mimetype"), "application/epub+zip",
            compress_type=zipfile.ZIP_STORED,
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


def escape(text: str) -> str:
    return (
        text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    )


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for stale in OUT.iterdir():
        stale.unlink()
    print(f"Writing the demo library into {OUT.relative_to(ROOT)}")

    manifest = []
    for book in BOOKS:
        tracks = narrate(book) if book.chapters else []
        cover(OUT / f"cover-{book.slug}.png", book.title, book.author, book.hue)
        if book.ebook:
            epub(OUT / f"{book.slug}.epub", book)

        entry = {
            "id": f"demo-{book.slug}",
            "title": book.title,
            "author": book.author,
            "year": book.year,
            "blurb": book.blurb,
            "cover": f"cover-{book.slug}",
            "narrator": "A synthesised voice" if tracks else None,
            "tracks": tracks,
            "file": {"resource": book.slug, "ext": "epub"} if book.ebook else None,
        }
        manifest.append(entry)
        length = sum(t["duration"] for t in tracks)
        kind = f"{len(tracks)} chapters, {length:.0f}s" if tracks else "ebook only"
        print(f"  {book.title[:34]:<34} {kind}")

    comic = ROOT / "Tests/Fixtures/sample.cbz"
    if comic.exists():
        shutil.copy(comic, OUT / "sample.cbz")
        cover(OUT / "cover-comic.png", "A Sample Comic", "Firelight", (38, 72, 48))
        manifest.append({
            "id": "demo-comic",
            "title": "A Sample Comic",
            "author": "Firelight",
            "year": "2026",
            "blurb": "A few generated pages, so the comic reader has something to open.",
            "cover": "cover-comic",
            "narrator": None,
            "tracks": [],
            "file": {"resource": "sample", "ext": "cbz"},
        })
        print(f"  {'A Sample Comic':<34} comic")

    # The manifest is what Swift reads, so measured durations never have to be
    # copied by hand into the catalogue.
    (OUT / "demo-library.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n"
    )

    size = sum(f.stat().st_size for f in OUT.iterdir()) / 1_048_576
    audio = sum(len(e["tracks"]) for e in manifest)
    print(f"\nDone. {len(manifest)} items, {audio} audio chapters, {size:.1f} MB.")


if __name__ == "__main__":
    main()
