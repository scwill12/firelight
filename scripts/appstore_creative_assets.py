#!/usr/bin/env python3
"""Uploads the App Store creative assets — the product page header and the
search results image — through the App Asset Library API.

These are not screenshots and they do not live on a version localisation.
They go into the app's asset library, and a *placement* is what actually
puts one on a surface. The two are separate calls, so an asset can sit in
the library unplaced, which is what Apple's own UI does when you upload
without saving.

Specs are read from `/v1/appAssetLibraryRefData` and matched on dimensions
rather than hard-coded, because the spec ids are Apple's and can change.

    export ASC_ISSUER_ID=...  ASC_KEY_ID=...  ASC_KEY_PATH=...
    python3 scripts/appstore_creative_assets.py            # dry run
    python3 scripts/appstore_creative_assets.py --apply

The key is read from the path in ASC_KEY_PATH and is never copied anywhere.
"""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import ssl
import struct
import sys
import time
import urllib.error
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE_ID = "com.colewilliams.firelight"
ROOT = pathlib.Path(__file__).resolve().parent.parent
CREATIVE = ROOT / "docs/creative"

# Which file goes on which surface. The spec is chosen by the file's own
# pixel size, so a re-rendered asset at a different supported size still
# finds its spec without editing this table.
ASSETS = [
    ("header-3840x1646.png", "PRODUCT_PAGE_HEADER_ASSET"),
    ("search-3840x2560.png", "APP_STORE_SEARCH_RESULTS_ASSET"),
]


def ssl_context() -> ssl.SSLContext:
    try:
        import certifi

        return ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        return ssl.create_default_context()


CONTEXT = ssl_context()
_token: str | None = None


def token() -> str:
    global _token
    if _token:
        return _token
    try:
        import jwt
    except ImportError:
        raise SystemExit("pip install pyjwt cryptography certifi")

    missing = [n for n in ("ASC_ISSUER_ID", "ASC_KEY_ID", "ASC_KEY_PATH") if not os.environ.get(n)]
    if missing:
        raise SystemExit("Set " + ", ".join(missing))

    key_path = pathlib.Path(os.path.expanduser(os.environ["ASC_KEY_PATH"]))
    if not key_path.is_file():
        raise SystemExit(f"No key at {key_path}")

    now = int(time.time())
    _token = jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 900,
         "aud": "appstoreconnect-v1"},
        key_path.read_text(),
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )
    return _token


def call(method: str, path: str, body: dict | None = None, raw: bytes | None = None,
         url: str | None = None, headers: dict | None = None) -> dict:
    target = url or f"{API}{path}"
    data = raw if raw is not None else (json.dumps(body).encode() if body else None)
    request = urllib.request.Request(target, data=data, method=method)
    if not url:
        request.add_header("Authorization", f"Bearer {token()}")
    if body is not None:
        request.add_header("Content-Type", "application/json")
    for name, value in (headers or {}).items():
        request.add_header(name, value)
    try:
        with urllib.request.urlopen(request, context=CONTEXT) as response:
            payload = response.read()
            return json.loads(payload) if payload else {}
    except urllib.error.HTTPError as error:
        raise SystemExit(f"{method} {target} → {error.code}\n{error.read().decode(errors='replace')[:1400]}")


def png_size(path: pathlib.Path) -> tuple[int, int]:
    header = path.read_bytes()[:33]
    if header[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path.name} is not a PNG")
    if header[25] not in (0, 2, 3):
        raise SystemExit(f"{path.name} has an alpha channel, which Apple rejects")
    return struct.unpack(">II", header[16:24])


def spec_for(width: int, height: int, placement: str) -> dict:
    """The one image spec that accepts these pixels on this surface."""
    data = call("GET", "/appAssetLibraryRefData")["data"]
    attributes = (data[0] if isinstance(data, list) else data)["attributes"]
    for spec in attributes["imageSpecs"]:
        if placement not in spec["compatiblePlacementTypes"]:
            continue
        d = spec["dimensions"]
        if d["minWidth"] <= width <= d["maxWidth"] and d["minHeight"] <= height <= d["maxHeight"]:
            return spec
    raise SystemExit(f"No spec accepts {width}x{height} for {placement}")


def existing(library: str, name: str) -> dict | None:
    for image in call("GET", f"/appAssetLibraries/{library}/images")["data"]:
        if image["attributes"]["fileName"] == name:
            return image
    return None


def upload(library: str, path: str, placement: str) -> str:
    source = CREATIVE / path
    blob = source.read_bytes()
    width, height = png_size(source)
    spec = spec_for(width, height, placement)
    print(f"\n{source.name}  {width}x{height}  {spec['aspectRatio']}  "
          f"{len(blob) / 1024:.0f} KB  spec {spec['shortName']}")

    already = existing(library, source.name)
    if already:
        print(f"  already in the library ({already['attributes']['state']}) — reusing")
        return already["id"]

    reserved = call("POST", "/appAssetLibraryImages", {
        "data": {
            "type": "appAssetLibraryImages",
            "attributes": {
                "fileName": source.name,
                "fileSize": len(blob),
                "category": "CREATIVE_ASSETS",
            },
            "relationships": {
                "assetLibrary": {"data": {"type": "appAssetLibraries", "id": library}}
            },
        }
    })["data"]

    for operation in reserved["attributes"]["uploadOperations"]:
        chunk = blob[operation["offset"]: operation["offset"] + operation["length"]]
        call(operation["method"], "", raw=chunk, url=operation["url"],
             headers={h["name"]: h["value"] for h in operation["requestHeaders"]})

    done = call("PATCH", f"/appAssetLibraryImages/{reserved['id']}", {
        "data": {
            "type": "appAssetLibraryImages",
            "id": reserved["id"],
            "attributes": {"uploaded": True},
        }
    })
    state = done.get("data", {}).get("attributes", {}).get("state", "?")
    print(f"  uploaded — {state}")
    return reserved["id"]


def place(image: str, placement: str, localization: str) -> None:
    """Puts an asset on a surface.

    A placement is scoped to a *localisation*, not to the app: the same
    library asset can sit on the header in one language and nowhere in
    another. Apple allows exactly one image per creative placement.
    """
    created = call("POST", "/appAssetLibraryPlacements", {
        "data": {
            "type": "appAssetLibraryPlacements",
            "attributes": {"placementType": placement},
            "relationships": {
                "image": {"data": {"type": "appAssetLibraryImages", "id": image}},
                "appStoreVersionLocalization": {
                    "data": {
                        "type": "appStoreVersionLocalizations",
                        "id": localization,
                    }
                },
            },
        }
    })
    print(f"  placed on {placement} ({created.get('data', {}).get('id', '?')})")


def localization_id(app: str) -> str:
    versions = call("GET", f"/apps/{app}/appStoreVersions?limit=1")["data"]
    if not versions:
        raise SystemExit("No App Store version to place assets on.")
    locales = call(
        "GET", f"/appStoreVersions/{versions[0]['id']}/appStoreVersionLocalizations"
    )["data"]
    english = next((l for l in locales if l["attributes"]["locale"] == "en-US"), locales[0])
    return english["id"]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="actually upload")
    parser.add_argument("--place", action="store_true",
                        help="also create the placement, not just the library asset")
    args = parser.parse_args()

    for name, placement in ASSETS:
        source = CREATIVE / name
        if not source.exists():
            raise SystemExit(f"Missing {source}. Run scripts/make_creative_assets.py first.")
        width, height = png_size(source)
        print(f"{name}  {width}x{height}  → {placement}")

    if not args.apply:
        print("\nDry run. Nothing uploaded. Re-run with --apply.")
        return

    app = call("GET", f"/apps?filter[bundleId]={BUNDLE_ID}")["data"]
    if not app:
        raise SystemExit(f"No app with bundle id {BUNDLE_ID}")
    library = call("GET", f"/apps/{app[0]['id']}/assetLibrary")["data"]["id"]
    print(f"\napp {app[0]['attributes']['name']} — asset library {library}")
    localization = localization_id(app[0]["id"]) if args.place else ""

    for name, placement in ASSETS:
        image = upload(library, name, placement)
        if args.place:
            place(image, placement, localization)


if __name__ == "__main__":
    sys.exit(main())
