#!/usr/bin/env python3
"""Creates Firelight's four tip products in App Store Connect.

Everything comes from `App/Firelight.storekit` — product ids, display names,
descriptions and prices — so the store and the app cannot disagree about what
a tip is called or costs. Edit that file, re-run this, and both follow.

Credentials come from the environment and the key from a path you control:

    export ASC_ISSUER_ID=...
    export ASC_KEY_ID=...
    export ASC_KEY_PATH=~/private_keys/AuthKey_XXXXXXXXXX.p8

    python3 scripts/appstore_tips.py            # dry run
    python3 scripts/appstore_tips.py --apply

Idempotent: a product, localization or price that already exists is left
alone, so a partial run can simply be repeated.

It does **not** submit anything, and it cannot finish the job on its own —
each product needs a review screenshot, which has to be uploaded by hand.
Until then every product sits in MISSING_METADATA, which is correct.
"""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import ssl
import time
import urllib.error
import urllib.request

import jwt

ROOT = pathlib.Path(__file__).resolve().parent.parent
STOREKIT = ROOT / "App/Firelight.storekit"
BUNDLE_ID = "com.colewilliams.firelight"
LOCALE = "en-US"
TERRITORY = "USA"

REVIEW_NOTE = (
    "A tip. Firelight is free and has no paid tier — this unlocks nothing and "
    "changes nothing about the app. It exists only for people who want to "
    "support the work."
)


def ssl_context() -> ssl.SSLContext:
    """A python.org build ships no CA bundle; certifi carries one."""
    try:
        import certifi

        return ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        return ssl.create_default_context()


CONTEXT = ssl_context()
V1 = "https://api.appstoreconnect.apple.com/v1"
V2 = "https://api.appstoreconnect.apple.com/v2"


def token() -> str:
    missing = [
        n for n in ("ASC_ISSUER_ID", "ASC_KEY_ID", "ASC_KEY_PATH") if not os.environ.get(n)
    ]
    if missing:
        raise SystemExit("Missing: " + ", ".join(missing))
    key = pathlib.Path(os.environ["ASC_KEY_PATH"]).expanduser()
    if not key.is_file():
        raise SystemExit(f"No private key at {key}")
    now = int(time.time())
    return jwt.encode(
        {
            "iss": os.environ["ASC_ISSUER_ID"],
            "iat": now,
            "exp": now + 900,
            "aud": "appstoreconnect-v1",
        },
        key.read_text(),
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"]},
    )


def call(method: str, url: str, body: dict | None = None, allow_404: bool = False) -> dict:
    data = json.dumps(body).encode() if body else None
    request = urllib.request.Request(url, data=data, method=method)
    request.add_header("Authorization", f"Bearer {token()}")
    if body:
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, context=CONTEXT) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        # "No price schedule yet" is reported as a 404 on the schedule itself,
        # which is an answer rather than a failure.
        if error.code == 404 and allow_404:
            return {}
        raise SystemExit(
            f"{method} {url} → {error.code}\n{error.read().decode(errors='replace')[:900]}"
        )


def tips() -> list[dict]:
    """The four products, straight out of the StoreKit configuration."""
    config = json.loads(STOREKIT.read_text())
    out = []
    for product in config["products"]:
        localization = product["localizations"][0]
        out.append(
            {
                "productId": product["productID"],
                "name": localization["displayName"],
                "description": localization["description"],
                "price": product["displayPrice"],
            }
        )
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    app = call("GET", f"{V1}/apps?filter[bundleId]={BUNDLE_ID}")["data"][0]["id"]
    existing = {
        p["attributes"]["productId"]: p
        for p in call("GET", f"{V1}/apps/{app}/inAppPurchasesV2?limit=200")["data"]
    }

    for tip in tips():
        product_id = tip["productId"]
        found = existing.get(product_id)
        action = "exists" if found else "create"
        print(f"{action:>7}  {product_id}  {tip['name']}  {tip['price']}")

        if not args.apply:
            continue

        if not found:
            found = call(
                "POST",
                f"{V2}/inAppPurchases",
                {
                    "data": {
                        "type": "inAppPurchases",
                        "attributes": {
                            "name": tip["name"],
                            "productId": product_id,
                            "inAppPurchaseType": "CONSUMABLE",
                            "reviewNote": REVIEW_NOTE,
                        },
                        "relationships": {"app": {"data": {"type": "apps", "id": app}}},
                    }
                },
            )["data"]
        iap = found["id"]

        localizations = call(
            "GET", f"{V2}/inAppPurchases/{iap}/inAppPurchaseLocalizations"
        )["data"]
        if not any(l["attributes"]["locale"] == LOCALE for l in localizations):
            call(
                "POST",
                f"{V1}/inAppPurchaseLocalizations",
                {
                    "data": {
                        "type": "inAppPurchaseLocalizations",
                        "attributes": {
                            "locale": LOCALE,
                            "name": tip["name"],
                            "description": tip["description"],
                        },
                        "relationships": {
                            "inAppPurchaseV2": {
                                "data": {"type": "inAppPurchases", "id": iap}
                            }
                        },
                    }
                },
            )
            print("         localization added")

        schedule = call("GET", f"{V2}/inAppPurchases/{iap}/iapPriceSchedule", allow_404=True)
        if schedule.get("data"):
            print("         price already set")
            continue

        points = call(
            "GET",
            f"{V2}/inAppPurchases/{iap}/pricePoints?filter[territory]={TERRITORY}&limit=200",
        )["data"]
        point = next(
            (p["id"] for p in points if p["attributes"]["customerPrice"] == tip["price"]),
            None,
        )
        if point is None:
            raise SystemExit(f"No {TERRITORY} price point at {tip['price']}")

        call(
            "POST",
            f"{V1}/inAppPurchasePriceSchedules",
            {
                "data": {
                    "type": "inAppPurchasePriceSchedules",
                    "relationships": {
                        "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap}},
                        "baseTerritory": {
                            "data": {"type": "territories", "id": TERRITORY}
                        },
                        "manualPrices": {
                            "data": [{"type": "inAppPurchasePrices", "id": "${p}"}]
                        },
                    },
                },
                "included": [
                    {
                        "type": "inAppPurchasePrices",
                        "id": "${p}",
                        "attributes": {"startDate": None},
                        "relationships": {
                            "inAppPurchasePricePoint": {
                                "data": {"type": "inAppPurchasePricePoints", "id": point}
                            }
                        },
                    }
                ],
            },
        )
        print(f"         price set to {tip['price']}")

    if not args.apply:
        print("\nDry run. Nothing created. Re-run with --apply.")
        return

    print("\nFinal states:")
    for product in call("GET", f"{V1}/apps/{app}/inAppPurchasesV2?limit=200")["data"]:
        attributes = product["attributes"]
        print(f"  {attributes['productId']:<42} {attributes['state']}")
    print(
        "\nMISSING_METADATA is expected: each product still needs a review "
        "screenshot, which has to be uploaded by hand."
    )


if __name__ == "__main__":
    main()
