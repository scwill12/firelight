#!/usr/bin/env python3
"""Pushes Firelight's listing copy and screenshots to App Store Connect.

Credentials are never in this file, never in the repository and never passed
on the command line. The script reads them from the environment, and reads
the private key from a path you control:

    export ASC_ISSUER_ID=...          # the UUID from Users and Access → Keys
    export ASC_KEY_ID=...             # the 10-character key id
    export ASC_KEY_PATH=~/private_keys/AuthKey_XXXXXXXXXX.p8

    python3 scripts/appstore_metadata.py            # dry run, changes nothing
    python3 scripts/appstore_metadata.py --apply    # writes the text fields
    python3 scripts/appstore_metadata.py --apply --screenshots

Dry run is the default on purpose: it prints what it would set, against the
real app record, so a wrong app or a wrong version shows up before anything
is written.

What it sets: subtitle, promotional text, description, keywords and What's
New on the version; privacy policy and support URLs on the app info. What it
deliberately does **not** touch: App Privacy answers, pricing, in-app
purchases, and submission. Those are attestations, money, and a one-way door.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import pathlib
import ssl
import time
import urllib.error
import urllib.request

import jwt


def ssl_context() -> ssl.SSLContext:
    """A context with a CA bundle that actually exists.

    A python.org framework build ships no CA certificates until someone runs
    `Install Certificates.command`, so every HTTPS call fails with
    CERTIFICATE_VERIFY_FAILED even though the host is perfectly reachable.
    `certifi` carries the bundle; fall back to the system defaults where it
    is not installed.
    """
    try:
        import certifi

        return ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        return ssl.create_default_context()


CONTEXT = ssl_context()

ROOT = pathlib.Path(__file__).resolve().parent.parent
API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE_ID = "com.colewilliams.firelight"
VERSION = "1.0"
LOCALE = "en-US"

# 6.9" captures. Apple still calls this display type APP_IPHONE_67.
SCREENSHOT_DIR = ROOT / "docs/store"
DISPLAY_TYPE = os.environ.get("ASC_DISPLAY_TYPE", "APP_IPHONE_67")

SUBTITLE = "Your self-hosted library"

PROMOTIONAL_TEXT = (
    "A free, open-source player and reader for your own Audiobookshelf "
    "server. No accounts, no ads, no tracking — just your library, on your "
    "phone, online or off."
)

KEYWORDS = "audiobookshelf,ebook,epub,m4b,player,listen,reader,podcast,offline,comics,chapters,sync"

WHATS_NEW = "First release."

PRIVACY_POLICY_URL = "https://scwill12.github.io/firelight-privacy/"
SUPPORT_URL = "https://github.com/scwill12/firelight/issues"

DESCRIPTION = """\
Firelight is a native iOS client for Audiobookshelf, the self-hosted \
audiobook and ebook server. If you run Audiobookshelf, Firelight is the app \
for listening and reading on your phone.

LISTENING
Chapter-aware playback with a scrubber that understands where chapters \
start. Adjustable speed per book, a sleep timer you can extend by shaking \
the phone, and smart rewind that backs up a little when you return after a \
pause — more when you have been away longer. Bookmarks sync to your server.

READING
EPUB, PDF and comics, with your highlights and notes kept across your \
devices through your own iCloud. Kindle files are converted on the phone. \
Follow along in print: tell Firelight how long your own copy is and it shows \
roughly where you would be on the page while you listen.

OFFLINE
Downloads are first-class. Your library, your covers, your place in every \
book — all cached, so the app opens and works with no connection at all. \
Positions are written down before they are sent, and reconciled when you are \
back.

NEVER LOSES YOUR PLACE
Positions sync both ways with your server. When Firelight finds a position \
from another device that is far from where you are, it asks before moving \
you instead of silently jumping.

THE REST OF THE SYSTEM
Live Activities and the Dynamic Island, home and lock screen widgets, Siri \
and Shortcuts, Handoff between devices, and a Kids Mode that can be locked \
behind your passcode.

PRIVACY
Firelight has no servers of its own, no analytics, no advertising and no \
crash reporting. It talks to the Audiobookshelf server you configure and to \
nothing else. It is free, with no paid tier — the tip jar unlocks nothing.

Firelight is open source under the MIT licence. It requires an Audiobookshelf \
server; it is not affiliated with the Audiobookshelf project."""


# --------------------------------------------------------------- credentials


def token() -> str:
    """A short-lived ES256 token. Apple rejects anything over 20 minutes."""
    missing = [
        name
        for name in ("ASC_ISSUER_ID", "ASC_KEY_ID", "ASC_KEY_PATH")
        if not os.environ.get(name)
    ]
    if missing:
        raise SystemExit(
            "Missing: " + ", ".join(missing) + "\n"
            "Create a key under App Store Connect → Users and Access → "
            "Integrations → App Store Connect API, then export the three "
            "values. The .p8 downloads once and cannot be downloaded again."
        )

    key_path = pathlib.Path(os.environ["ASC_KEY_PATH"]).expanduser()
    if not key_path.is_file():
        raise SystemExit(f"No private key at {key_path}")

    now = int(time.time())
    return jwt.encode(
        {
            "iss": os.environ["ASC_ISSUER_ID"],
            "iat": now,
            "exp": now + 15 * 60,
            "aud": "appstoreconnect-v1",
        },
        key_path.read_text(),
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


# ----------------------------------------------------------------- transport


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
        detail = error.read().decode(errors="replace")
        raise SystemExit(f"{method} {target} → {error.code}\n{detail[:1200]}")


# -------------------------------------------------------------------- lookups


def app_id() -> str:
    found = call("GET", f"/apps?filter[bundleId]={BUNDLE_ID}")["data"]
    if not found:
        raise SystemExit(f"No app with bundle id {BUNDLE_ID} on this account.")
    app = found[0]
    print(f"app: {app['attributes']['name']} ({app['id']})")
    return app["id"]


def version_id(app: str) -> tuple[str, bool]:
    """The version's id, and whether it is the app's first."""
    everything = call("GET", f"/apps/{app}/appStoreVersions")["data"]
    matching = [
        v for v in everything if v["attributes"]["versionString"] == VERSION
    ]
    if not matching:
        raise SystemExit(f"No version {VERSION}. Create it in App Store Connect first.")
    version = matching[0]
    first = len(everything) == 1
    print(
        f"version: {VERSION} ({version['attributes']['appStoreState']})"
        + ("  — first release" if first else "")
    )
    return version["id"], first


def localization_id(version: str) -> str:
    for entry in call("GET", f"/appStoreVersions/{version}/appStoreVersionLocalizations")["data"]:
        if entry["attributes"]["locale"] == LOCALE:
            return entry["id"]
    raise SystemExit(f"No {LOCALE} localization on version {VERSION}.")


def info_localization_id(app: str) -> str:
    infos = call("GET", f"/apps/{app}/appInfos")["data"]
    for entry in call("GET", f"/appInfos/{infos[0]['id']}/appInfoLocalizations")["data"]:
        if entry["attributes"]["locale"] == LOCALE:
            return entry["id"]
    raise SystemExit(f"No {LOCALE} app info localization.")


# -------------------------------------------------------------------- writing


def set_text(
    version_localization: str, info_localization: str, is_first_release: bool, apply: bool
) -> None:
    # The split is not obvious and App Store Connect rejects a guess outright:
    # `subtitle` belongs to the app *info* alongside the name and the privacy
    # policy, while `supportUrl` belongs to the *version* alongside the
    # description. Mixing them up returns ENTITY_ERROR.ATTRIBUTE.UNKNOWN and
    # writes nothing, which is at least a safe way to be wrong.
    version_fields = {
        "promotionalText": PROMOTIONAL_TEXT,
        "description": DESCRIPTION,
        "keywords": KEYWORDS,
        "supportUrl": SUPPORT_URL,
    }
    # "What's New" describes what changed since the last version, so App
    # Store Connect refuses it on a first release — STATE_ERROR, "cannot be
    # edited at this time". Only send it once there is something to be new
    # against.
    if not is_first_release:
        version_fields["whatsNew"] = WHATS_NEW
    info_fields = {
        "subtitle": SUBTITLE,
        "privacyPolicyUrl": PRIVACY_POLICY_URL,
    }

    for name, value in {**version_fields, **info_fields}.items():
        preview = value.replace("\n", " ")[:72]
        print(f"  {name:<18} {len(value):>5} chars  {preview}…")

    if not apply:
        print("\nDry run. Nothing written. Re-run with --apply.")
        return

    call("PATCH", f"/appStoreVersionLocalizations/{version_localization}", {
        "data": {
            "type": "appStoreVersionLocalizations",
            "id": version_localization,
            "attributes": version_fields,
        }
    })
    call("PATCH", f"/appInfoLocalizations/{info_localization}", {
        "data": {
            "type": "appInfoLocalizations",
            "id": info_localization,
            "attributes": info_fields,
        }
    })
    print("\nText fields written.")


def upload_screenshots(version_localization: str, apply: bool) -> None:
    shots = sorted(SCREENSHOT_DIR.glob("*.png"))
    if not shots:
        raise SystemExit(f"No screenshots in {SCREENSHOT_DIR}.")

    print(f"\nscreenshots ({DISPLAY_TYPE}):")
    for shot in shots:
        print(f"  {shot.name}  {shot.stat().st_size / 1024:.0f} KB")
    if not apply:
        print("Dry run. Nothing uploaded.")
        return

    sets = call(
        "GET", f"/appStoreVersionLocalizations/{version_localization}/appScreenshotSets"
    )["data"]
    existing = next(
        (s for s in sets if s["attributes"]["screenshotDisplayType"] == DISPLAY_TYPE),
        None,
    )
    if existing:
        set_id = existing["id"]
    else:
        set_id = call("POST", "/appScreenshotSets", {
            "data": {
                "type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": DISPLAY_TYPE},
                "relationships": {
                    "appStoreVersionLocalization": {
                        "data": {
                            "type": "appStoreVersionLocalizations",
                            "id": version_localization,
                        }
                    }
                },
            }
        })["data"]["id"]

    for shot in shots:
        blob = shot.read_bytes()
        reserved = call("POST", "/appScreenshots", {
            "data": {
                "type": "appScreenshots",
                "attributes": {"fileName": shot.name, "fileSize": len(blob)},
                "relationships": {
                    "appScreenshotSet": {
                        "data": {"type": "appScreenshotSets", "id": set_id}
                    }
                },
            }
        })["data"]

        for operation in reserved["attributes"]["uploadOperations"]:
            chunk = blob[operation["offset"]: operation["offset"] + operation["length"]]
            call(
                operation["method"],
                "",
                raw=chunk,
                url=operation["url"],
                headers={h["name"]: h["value"] for h in operation["requestHeaders"]},
            )

        call("PATCH", f"/appScreenshots/{reserved['id']}", {
            "data": {
                "type": "appScreenshots",
                "id": reserved["id"],
                "attributes": {"uploaded": True},
            }
        })
        print(f"  uploaded {shot.name}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="actually write")
    parser.add_argument("--screenshots", action="store_true", help="also upload screenshots")
    args = parser.parse_args()

    app = app_id()
    version, first_release = version_id(app)
    version_localization = localization_id(version)
    info_localization = info_localization_id(app)

    print()
    set_text(version_localization, info_localization, first_release, args.apply)
    if args.screenshots:
        upload_screenshots(version_localization, args.apply)

    if args.apply:
        print(
            "\nNot touched, on purpose: App Privacy, pricing, in-app purchases, "
            "and submission."
        )


if __name__ == "__main__":
    main()
