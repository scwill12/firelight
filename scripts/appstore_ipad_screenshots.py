#!/usr/bin/env python3
"""Uploads the iPad screenshot set.

Apple requires an iPad set once the app declares iPad support — a submission
without one is refused with STATE_ERROR.SCREENSHOT_REQUIRED.IPAD_13_PROFILE,
which is only visible when you try to add the version to a review submission.

`APP_IPAD_PRO_3GEN_129` is the display type that accepts the iPad Pro
13-inch's native 2064 x 2752, and is the only iPad type this account offers
above 11 inches.

    export ASC_ISSUER_ID=...  ASC_KEY_ID=...  ASC_KEY_PATH=...
    python3 scripts/appstore_ipad_screenshots.py            # dry run
    python3 scripts/appstore_ipad_screenshots.py --apply

Idempotent: a screenshot already in the set under the same file name is left
alone unless --replace is passed.
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
DISPLAY_TYPE = "APP_IPAD_PRO_3GEN_129"
ROOT = pathlib.Path(__file__).resolve().parent.parent
SHOTS = ROOT / "docs/store-ipad"


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
        key_path.read_text(), algorithm="ES256",
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
        raise SystemExit(
            f"{method} {target} → {error.code}\n{error.read().decode(errors='replace')[:1200]}"
        )


def png_size(path: pathlib.Path) -> tuple[int, int]:
    header = path.read_bytes()[:33]
    if header[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path.name} is not a PNG")
    return struct.unpack(">II", header[16:24])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--replace", action="store_true")
    args = parser.parse_args()

    shots = sorted(SHOTS.glob("*.png"))
    if not shots:
        raise SystemExit(f"No screenshots in {SHOTS}")
    for shot in shots:
        width, height = png_size(shot)
        print(f"  {shot.name:18} {width}x{height}  {shot.stat().st_size / 1024:.0f} KB")

    if not args.apply:
        print(f"\nDry run for {DISPLAY_TYPE}. Nothing uploaded.")
        return

    app = call("GET", f"/apps?filter[bundleId]={BUNDLE_ID}")["data"]
    version = call("GET", f"/apps/{app[0]['id']}/appStoreVersions?limit=1")["data"][0]
    localization = call(
        "GET", f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations"
    )["data"]
    loc = next((l for l in localization if l["attributes"]["locale"] == "en-US"), localization[0])

    sets = call("GET", f"/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")["data"]
    found = next(
        (s for s in sets if s["attributes"]["screenshotDisplayType"] == DISPLAY_TYPE), None
    )
    if found:
        set_id = found["id"]
        print(f"\nreusing existing {DISPLAY_TYPE} set")
    else:
        set_id = call("POST", "/appScreenshotSets", {
            "data": {
                "type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": DISPLAY_TYPE},
                "relationships": {
                    "appStoreVersionLocalization": {
                        "data": {"type": "appStoreVersionLocalizations", "id": loc["id"]}
                    }
                },
            }
        })["data"]["id"]
        print(f"\ncreated {DISPLAY_TYPE} set")

    present = {
        s["attributes"].get("fileName"): s["id"]
        for s in call("GET", f"/appScreenshotSets/{set_id}/appScreenshots")["data"]
    }

    for shot in shots:
        if shot.name in present:
            if not args.replace:
                print(f"  {shot.name}: already present — left alone")
                continue
            call("DELETE", f"/appScreenshots/{present[shot.name]}")

        blob = shot.read_bytes()
        reserved = call("POST", "/appScreenshots", {
            "data": {
                "type": "appScreenshots",
                "attributes": {"fileName": shot.name, "fileSize": len(blob)},
                "relationships": {
                    "appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}
                },
            }
        })["data"]
        for operation in reserved["attributes"]["uploadOperations"]:
            chunk = blob[operation["offset"]: operation["offset"] + operation["length"]]
            call(operation["method"], "", raw=chunk, url=operation["url"],
                 headers={h["name"]: h["value"] for h in operation["requestHeaders"]})
        call("PATCH", f"/appScreenshots/{reserved['id']}", {
            "data": {"type": "appScreenshots", "id": reserved["id"],
                     "attributes": {"uploaded": True}}
        })
        print(f"  {shot.name}: uploaded")

    print("\nset now holds:")
    for s in call("GET", f"/appScreenshotSets/{set_id}/appScreenshots")["data"]:
        a = s["attributes"]
        state = (a.get("assetDeliveryState") or {}).get("state")
        errors = (a.get("assetDeliveryState") or {}).get("errors")
        print(f"  {a.get('fileName'):18} {state}  {errors or ''}")


if __name__ == "__main__":
    sys.exit(main())
