#!/usr/bin/env python3
"""Attaches the App Review screenshot to each tip product.

Every in-app purchase needs one screenshot showing the reviewer where the
purchase lives in the app. It is the only thing that holds the four tips at
`MISSING_METADATA`, and a product in that state is not fetchable by StoreKit
at all — so this is also what makes the tips testable in sandbox.

One image covers all four, because they are four rows on one screen.

    export ASC_ISSUER_ID=...  ASC_KEY_ID=...  ASC_KEY_PATH=...
    python3 scripts/appstore_tip_screenshots.py path/to/tip-jar.png
    python3 scripts/appstore_tip_screenshots.py path/to/tip-jar.png --apply

Idempotent: a product that already carries a screenshot is left alone unless
--replace is passed.
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
        raise SystemExit(
            f"{method} {target} → {error.code}\n{error.read().decode(errors='replace')[:1200]}"
        )


def png_size(path: pathlib.Path) -> tuple[int, int]:
    header = path.read_bytes()[:33]
    if header[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path.name} is not a PNG")
    return struct.unpack(">II", header[16:24])


def existing_screenshot(iap: str) -> dict | None:
    """The screenshot already attached, if any.

    Read through `/v2`: in-app purchases themselves are a v2 resource, while
    the screenshot you create is a v1 one. Mixing them up gives a confusing
    `The relationship 'appStoreReviewScreenshot' does not exist`.
    """
    found = call(
        "GET", "",
        url=f"https://api.appstoreconnect.apple.com/v2/inAppPurchases/{iap}"
            "/appStoreReviewScreenshot",
        headers={"Authorization": f"Bearer {token()}"},
    ).get("data")
    return found or None


def attach(iap: str, label: str, image: pathlib.Path, replace: bool) -> None:
    current = existing_screenshot(iap)
    if current and not replace:
        print(f"  {label}: already has {current['attributes'].get('fileName')} — left alone")
        return
    if current and replace:
        call("DELETE", f"/inAppPurchaseAppStoreReviewScreenshots/{current['id']}")
        print(f"  {label}: removed the previous screenshot")

    blob = image.read_bytes()
    reserved = call("POST", "/inAppPurchaseAppStoreReviewScreenshots", {
        "data": {
            "type": "inAppPurchaseAppStoreReviewScreenshots",
            "attributes": {"fileName": image.name, "fileSize": len(blob)},
            "relationships": {
                "inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap}}
            },
        }
    })["data"]

    for operation in reserved["attributes"]["uploadOperations"]:
        chunk = blob[operation["offset"]: operation["offset"] + operation["length"]]
        call(operation["method"], "", raw=chunk, url=operation["url"],
             headers={h["name"]: h["value"] for h in operation["requestHeaders"]})

    done = call("PATCH", f"/inAppPurchaseAppStoreReviewScreenshots/{reserved['id']}", {
        "data": {
            "type": "inAppPurchaseAppStoreReviewScreenshots",
            "id": reserved["id"],
            "attributes": {"uploaded": True},
        }
    })
    state = (done.get("data", {}).get("attributes", {})
             .get("assetDeliveryState", {}).get("state", "?"))
    print(f"  {label}: uploaded — {state}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", help="PNG of the tip jar screen")
    parser.add_argument("--apply", action="store_true", help="actually upload")
    parser.add_argument("--replace", action="store_true",
                        help="replace a screenshot that is already attached")
    args = parser.parse_args()

    image = pathlib.Path(args.image).resolve()
    if not image.is_file():
        raise SystemExit(f"No image at {image}")
    width, height = png_size(image)
    print(f"{image.name}  {width}x{height}  {image.stat().st_size / 1024:.0f} KB")

    app = call("GET", f"/apps?filter[bundleId]={BUNDLE_ID}")["data"]
    if not app:
        raise SystemExit(f"No app with bundle id {BUNDLE_ID}")
    products = call("GET", f"/apps/{app[0]['id']}/inAppPurchasesV2?limit=20")["data"]
    print(f"\n{len(products)} in-app purchases:")
    for p in products:
        print(f"  {p['attributes']['productId'].split('.')[-1]:8} {p['attributes']['state']}")

    if not args.apply:
        print("\nDry run. Nothing uploaded. Re-run with --apply.")
        return

    print("\nattaching:")
    for p in products:
        attach(p["id"], p["attributes"]["productId"].split(".")[-1], image, args.replace)

    print("\nstate now:")
    for p in call("GET", f"/apps/{app[0]['id']}/inAppPurchasesV2?limit=20")["data"]:
        print(f"  {p['attributes']['productId'].split('.')[-1]:8} {p['attributes']['state']}")


if __name__ == "__main__":
    sys.exit(main())
