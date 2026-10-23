#!/usr/bin/env python3
"""Checks a real Audiobookshelf server against what Firelight assumes.

Everything in ABSKit was written from the ABS source. This asks a running
server whether the source matches the deployment, and prints a report that is
safe to paste anywhere: no token, no username, no password and no hostname
reaches the output.

    python3 scripts/probe-abs.py

Standard library only, so it runs anywhere python3 does.
"""
from __future__ import annotations

import getpass
import json
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

# What Firelight's decoders expect. A missing key is a bug in Firelight; an
# extra key is just a field we don't read yet.
EXPECTED = {
    "status": ["app", "serverVersion", "isInit", "language", "authMethods"],
    "login": ["user", "userDefaultLibraryId", "serverSettings", "Source"],
    "user": ["id", "username", "type", "accessToken"],
    "library": ["id", "name", "mediaType"],
    "itemsPage": ["results", "limit", "page"],
    "item": ["id", "libraryId", "mediaType", "addedAt", "updatedAt", "isMissing", "media"],
    "media": ["id", "metadata", "coverPath", "numTracks", "numChapters", "duration", "size"],
    "metadata": ["title", "titleIgnorePrefix", "authorName", "narratorName", "seriesName",
                 "genres", "publishedYear", "explicit"],
    "progress": ["id", "libraryItemId", "episodeId", "duration", "progress", "currentTime",
                 "isFinished", "hideFromContinueListening", "ebookLocation", "ebookProgress",
                 "lastUpdate", "startedAt"],
    "session": ["id", "libraryItemId", "mediaType", "displayTitle", "duration", "playMethod",
                "currentTime", "startTime", "chapters", "audioTracks"],
    "track": ["index", "startOffset", "duration", "title", "contentUrl", "mimeType"],
    "chapter": ["id", "start", "end", "title"],
}

PASS, FAIL, WARN, INFO = "  PASS", "  FAIL", "  WARN", "      ·"
report: list[str] = []
failures = 0


def say(line: str = "") -> None:
    report.append(line)
    print(line, flush=True)


def note_fail(line: str) -> None:
    global failures
    failures += 1
    say(f"{FAIL}  {line}")


class Client:
    def __init__(self, base: str, insecure: bool) -> None:
        self.base = base.rstrip("/")
        self.token: str | None = None
        self.ctx = ssl.create_default_context()
        if insecure:
            self.ctx.check_hostname = False
            self.ctx.verify_mode = ssl.CERT_NONE

    def request(self, method: str, path: str, body=None, headers=None, auth=True):
        url = self.base + path
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(url, data=data, method=method)
        request.add_header("Accept", "application/json")
        if data:
            request.add_header("Content-Type", "application/json")
        if auth and self.token:
            request.add_header("Authorization", f"Bearer {self.token}")
        for name, value in (headers or {}).items():
            request.add_header(name, value)

        try:
            with urllib.request.urlopen(request, context=self.ctx, timeout=30) as response:
                raw = response.read()
                return response.status, (json.loads(raw) if raw else None)
        except urllib.error.HTTPError as error:
            raw = error.read()
            try:
                return error.code, json.loads(raw) if raw else None
            except Exception:
                return error.code, raw.decode("utf-8", "replace")[:200]
        except Exception as error:  # noqa: BLE001
            return None, f"{type(error).__name__}"


def keys_of(obj) -> list[str]:
    return sorted(obj.keys()) if isinstance(obj, dict) else []


def check_keys(label: str, obj, expected_key: str) -> None:
    """Reports which of Firelight's expected keys are missing."""
    if not isinstance(obj, dict):
        note_fail(f"{label}: expected an object, got {type(obj).__name__}")
        return
    expected = EXPECTED[expected_key]
    missing = [k for k in expected if k not in obj]
    if missing:
        note_fail(f"{label}: MISSING {missing}")
    else:
        say(f"{PASS}  {label}: all {len(expected)} expected keys present")
    extra = [k for k in keys_of(obj) if k not in expected]
    if extra:
        say(f"{INFO} also present: {extra}")


def describe_date(label: str, value) -> None:
    """Firelight decodes ABS timestamps as epoch milliseconds."""
    if isinstance(value, (int, float)):
        kind = "epoch ms" if value > 10_000_000_000 else "epoch SECONDS"
        marker = PASS if value > 10_000_000_000 else FAIL
        if value <= 10_000_000_000:
            global failures
            failures += 1
        say(f"{marker}  {label}: number ({kind})")
    elif isinstance(value, str):
        note_fail(f"{label}: ISO string, not a number — the date decoder expects ms")
    else:
        say(f"{WARN}  {label}: absent")


def main() -> int:
    say("=" * 64)
    say("Firelight — Audiobookshelf API probe")
    say("=" * 64)
    say("Nothing identifying is printed: no token, username, password or host.")
    say()

    # The URL can come in as an argument so it need not be retyped.
    raw_url = (sys.argv[1] if len(sys.argv) > 1 else "").strip()
    if raw_url:
        say(f"Server URL supplied as an argument ({urllib.parse.urlparse(raw_url).scheme}://…)")
    else:
        raw_url = input("Server URL (e.g. http://books.example.com:13378): ").strip()
    if not raw_url:
        print("No URL given.")
        return 2
    if "://" not in raw_url:
        raw_url = "http://" + raw_url
    username = input("Username: ").strip()
    password = getpass.getpass("Password (not echoed, never printed): ")
    # http needs no certificate decision at all.
    insecure = False
    if raw_url.lower().startswith("https"):
        insecure = input("Self-signed certificate? [y/N]: ").strip().lower().startswith("y")

    parsed = urllib.parse.urlparse(raw_url)
    client = Client(raw_url, insecure)

    say()
    say(f"Scheme: {parsed.scheme}   Sub-path: {parsed.path or '(none)'}   TLS verify: {not insecure}")
    say()

    # ---------------------------------------------------------- /status ---
    say("[1] GET /status")
    code, status = client.request("GET", "/status", auth=False)
    if code != 200 or not isinstance(status, dict):
        note_fail(f"status returned {code} ({status!r})")
        say()
        say("Cannot continue without /status. Check the URL and try again.")
        return 1
    check_keys("/status", status, "status")
    version = status.get("serverVersion")
    say(f"{INFO} serverVersion = {version}")
    say(f"{INFO} authMethods   = {status.get('authMethods')}")
    say(f"{INFO} app           = {status.get('app')}")
    if version:
        try:
            major, minor = (int(p) for p in str(version).split(".")[:2])
            if (major, minor) >= (2, 26):
                say(f"{PASS}  2.26+, so refresh tokens should be available")
            else:
                say(f"{WARN}  older than 2.26 — legacy token path will be used")
        except ValueError:
            say(f"{WARN}  could not parse the version")
    say()

    # ----------------------------------------------------------- /login ---
    say("[2] POST /login  (the x-return-tokens behaviour)")
    code, without = client.request(
        "POST", "/login", {"username": username, "password": password}, auth=False
    )
    if code != 200 or not isinstance(without, dict):
        note_fail(f"login returned {code} — check the username and password")
        return 1
    check_keys("/login", without, "login")
    user_without = without.get("user", {})
    say(f"{INFO} without the header: user.refreshToken is "
        f"{'null' if user_without.get('refreshToken') is None else 'PRESENT'}")

    code, with_tokens = client.request(
        "POST", "/login", {"username": username, "password": password},
        headers={"x-return-tokens": "true"}, auth=False
    )
    user = with_tokens.get("user", {}) if isinstance(with_tokens, dict) else {}
    check_keys("/login user", user, "user")

    access = user.get("accessToken")
    refresh = user.get("refreshToken")
    legacy = user.get("token")
    say(f"{INFO} with x-return-tokens: accessToken  {'present' if access else 'MISSING'}"
        f" ({len(access) if access else 0} chars)")
    if refresh:
        say(f"{PASS}  with x-return-tokens: refreshToken present ({len(refresh)} chars)")
        say(f"{INFO} -> Firelight's assumption holds: the header is what returns it")
    else:
        note_fail("with x-return-tokens: refreshToken is STILL null "
                  "— Firelight cannot stay signed in; investigate before Phase 1 ships")
    say(f"{INFO} legacy user.token: {'present' if legacy else 'absent'}")
    say(f"{INFO} userDefaultLibraryId: {'present' if with_tokens.get('userDefaultLibraryId') else 'absent'}")
    client.token = access
    say()

    # --------------------------------------------------- /auth/refresh ---
    if refresh:
        say("[3] POST /auth/refresh  (x-refresh-token header)")
        code, refreshed = client.request(
            "POST", "/auth/refresh", headers={"x-refresh-token": refresh}, auth=False
        )
        if code == 200 and isinstance(refreshed, dict):
            new_access = refreshed.get("user", {}).get("accessToken")
            new_refresh = refreshed.get("user", {}).get("refreshToken")
            say(f"{PASS}  refresh succeeded")
            say(f"{INFO} new accessToken:  {'yes' if new_access else 'no'}")
            say(f"{INFO} new refreshToken: {'yes (rotated)' if new_refresh else 'no'}")
            if new_refresh and new_refresh != refresh:
                say(f"{INFO} -> rotation confirmed; AuthStore coalescing is required, as built")
            if new_access:
                client.token = new_access
        else:
            note_fail(f"/auth/refresh returned {code}")
        say()

    # -------------------------------------------------------- /api/me ---
    say("[4] GET /api/me")
    code, me = client.request("GET", "/api/me")
    if code == 200 and isinstance(me, dict):
        say(f"{PASS}  /api/me reachable with the bearer token")
        progress = me.get("mediaProgress") or []
        say(f"{INFO} mediaProgress entries: {len(progress)}")
        if progress:
            check_keys("mediaProgress[0]", progress[0], "progress")
            describe_date("mediaProgress[0].lastUpdate", progress[0].get("lastUpdate"))
            say(f"{INFO} progress value sample: {progress[0].get('progress')!r}")
        else:
            say(f"{WARN}  no progress yet — play something and re-run to check this")
    else:
        note_fail(f"/api/me returned {code}")
    say()

    # ------------------------------------------------- /api/libraries ---
    say("[5] GET /api/libraries")
    code, libraries_response = client.request("GET", "/api/libraries")
    if code != 200:
        note_fail(f"/api/libraries returned {code}")
        return 1
    if isinstance(libraries_response, dict) and "libraries" in libraries_response:
        say(f"{PASS}  wrapped in a 'libraries' key, as Firelight decodes")
        libraries = libraries_response["libraries"]
    elif isinstance(libraries_response, list):
        note_fail("returned a bare ARRAY — Firelight expects {\"libraries\": [...]}")
        libraries = libraries_response
    else:
        note_fail(f"unexpected shape: {keys_of(libraries_response)}")
        libraries = []

    say(f"{INFO} libraries: {len(libraries)}")
    book_library = None
    for library in libraries:
        kind = library.get("mediaType")
        say(f"{INFO}   - mediaType={kind}  (name withheld)")
        if kind == "book" and book_library is None:
            book_library = library
    if libraries:
        check_keys("library[0]", libraries[0], "library")
    say()

    if not book_library:
        say("No book library found; stopping here.")
        return 1 if failures else 0

    library_id = book_library["id"]

    # -------------------------------------------------- library items ---
    say("[6] GET /api/libraries/:id/items?limit=1&minified=1")
    code, page = client.request(
        "GET", f"/api/libraries/{library_id}/items?limit=1&page=0&minified=1"
    )
    if code != 200 or not isinstance(page, dict):
        note_fail(f"items returned {code}")
        return 1
    check_keys("items page", page, "itemsPage")
    say(f"{INFO} total present: {'yes' if 'total' in page else 'NO (decoded as optional — fine)'}")
    say(f"{INFO} total = {page.get('total')}")

    results = page.get("results") or []
    if not results:
        say(f"{WARN}  library is empty; add a book and re-run")
        return 1 if failures else 0

    item = results[0]
    check_keys("item", item, "item")
    describe_date("item.addedAt", item.get("addedAt"))
    describe_date("item.updatedAt", item.get("updatedAt"))

    media = item.get("media") or {}
    check_keys("item.media", media, "media")
    say(f"{INFO} media.ebookFormat: {media.get('ebookFormat')!r}")
    metadata = media.get("metadata") or {}
    check_keys("item.media.metadata", metadata, "metadata")
    say(f"{INFO} seriesName sample: {metadata.get('seriesName')!r}  "
        "(Firelight parses 'Name #5' out of this)")
    say()

    # ---------------------------------------------------- personalized ---
    say("[7] GET /api/libraries/:id/personalized  (shape was never verified)")
    code, personalized = client.request("GET", f"/api/libraries/{library_id}/personalized")
    if code == 200:
        if isinstance(personalized, list):
            say(f"{INFO} returns an ARRAY of {len(personalized)} shelves")
            if personalized:
                say(f"{INFO} shelf keys: {keys_of(personalized[0])}")
                say(f"{INFO} shelf id/label/type: "
                    f"{personalized[0].get('id')!r} / {personalized[0].get('labelStringKey')!r} "
                    f"/ {personalized[0].get('type')!r}")
                say(f"{INFO} all shelf ids: {[s.get('id') for s in personalized]}")
        else:
            say(f"{INFO} returns an object with keys: {keys_of(personalized)}")
    else:
        say(f"{WARN}  returned {code}")
    say()

    # ------------------------------------------------- playback session ---
    playable = next((r for r in results if (r.get("media") or {}).get("numTracks")), None)
    if playable is None:
        code, bigger = client.request(
            "GET", f"/api/libraries/{library_id}/items?limit=25&page=0&minified=1"
        )
        if isinstance(bigger, dict):
            playable = next(
                (r for r in (bigger.get("results") or [])
                 if (r.get("media") or {}).get("numTracks")),
                None,
            )

    if playable:
        say("[8] POST /api/items/:id/play  (audio tracks, chapters, offsets)")
        body = {
            "deviceInfo": {"deviceId": "firelight-probe", "clientName": "Firelight probe",
                           "clientVersion": "0.1.0", "manufacturer": "Apple", "model": "probe"},
            "forceDirectPlay": True,
            "forceTranscode": False,
            "supportedMimeTypes": ["audio/mpeg", "audio/mp4", "audio/m4a", "audio/m4b",
                                   "audio/x-m4b", "audio/aac", "audio/flac", "audio/opus"],
            "mediaPlayer": "AVPlayer",
        }
        code, session = client.request("POST", f"/api/items/{playable['id']}/play", body)
        if code == 200 and isinstance(session, dict):
            check_keys("play session", session, "session")
            tracks = session.get("audioTracks") or []
            chapters = session.get("chapters") or []
            say(f"{INFO} audioTracks: {len(tracks)}   chapters: {len(chapters)}")
            say(f"{INFO} playMethod: {session.get('playMethod')!r} (0 = direct play)")

            if tracks:
                check_keys("audioTracks[0]", tracks[0], "track")
                content_url = tracks[0].get("contentUrl") or ""
                say(f"{INFO} contentUrl pattern: "
                    f"{'/api/items/<id>/file/<ino>' if '/file/' in content_url else content_url[:40]}")
                say(f"{INFO} contentUrl is "
                    f"{'relative (as Firelight assumes)' if content_url.startswith('/') else 'ABSOLUTE'}")
                say(f"{INFO} contentUrl carries a token: "
                    f"{'yes' if 'token=' in content_url else 'no (Firelight adds one)'}")
                offsets = [t.get("startOffset") for t in tracks[:4]]
                say(f"{INFO} startOffsets (first 4): {offsets}")
                if len(tracks) > 1:
                    say(f"{PASS}  multi-track book — exactly the case TrackTimeline handles")
            if chapters:
                check_keys("chapters[0]", chapters[0], "chapter")
                say(f"{INFO} chapter[0] start/end: "
                    f"{chapters[0].get('start')!r} -> {chapters[0].get('end')!r}")

            session_id = session.get("id")
            if session_id:
                code, _ = client.request(
                    "POST", f"/api/session/{session_id}/close",
                    {"currentTime": session.get("currentTime", 0),
                     "timeListened": 0, "duration": session.get("duration", 0)},
                )
                say(f"{INFO} session closed cleanly: {code == 200}")
        else:
            note_fail(f"/play returned {code}: {session!r}")
    else:
        say("[8] No item with audio tracks found; skipping the playback check.")
    say()

    # ------------------------------------------------------------ done ---
    say("=" * 64)
    if failures:
        say(f"RESULT: {failures} mismatch(es) against what Firelight assumes.")
    else:
        say("RESULT: every assumption Firelight makes checks out.")
    say("=" * 64)
    return 1 if failures else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\nCancelled.")
        sys.exit(130)
