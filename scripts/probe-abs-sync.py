#!/usr/bin/env python3
"""Checks the progress and offline-sync paths against a real server.

Probe 1 covered everything read-only. This one covers the writes, which is
where Phase 4 lives and where the first probe found a failure: closing a
playback session did not return 200.

It WRITES to the server: it records a position on one book, posts an offline
session, then deletes the progress it created. Run it against a test server.

    python3 scripts/probe-abs-sync.py http://host:13378

No token, username, password or hostname reaches the output.
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

PASS, FAIL, WARN, INFO = "  PASS", "  FAIL", "  WARN", "      ·"
failures = 0

EXPECTED_PROGRESS = [
    "id", "libraryItemId", "episodeId", "mediaItemId", "mediaItemType", "duration",
    "progress", "currentTime", "isFinished", "hideFromContinueListening",
    "ebookLocation", "ebookProgress", "lastUpdate", "startedAt", "finishedAt",
]


def say(line: str = "") -> None:
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
        request = urllib.request.Request(
            self.base + path,
            data=json.dumps(body).encode() if body is not None else None,
            method=method,
        )
        request.add_header("Accept", "application/json")
        if body is not None:
            request.add_header("Content-Type", "application/json")
        if auth and self.token:
            request.add_header("Authorization", f"Bearer {self.token}")
        for name, value in (headers or {}).items():
            request.add_header(name, value)
        try:
            with urllib.request.urlopen(request, context=self.ctx, timeout=30) as response:
                raw = response.read()
                try:
                    return response.status, (json.loads(raw) if raw else None)
                except json.JSONDecodeError:
                    return response.status, raw.decode("utf-8", "replace")[:200]
        except urllib.error.HTTPError as error:
            raw = error.read()
            try:
                return error.code, json.loads(raw) if raw else None
            except Exception:
                return error.code, raw.decode("utf-8", "replace")[:200]
        except Exception as error:  # noqa: BLE001
            return None, type(error).__name__


def main() -> int:
    say("=" * 64)
    say("Firelight — progress and offline-sync probe")
    say("=" * 64)
    say("This WRITES to the server: it records a position on one book, posts")
    say("an offline session, then deletes the progress it created.")
    say()

    raw_url = (sys.argv[1] if len(sys.argv) > 1 else "").strip()
    if not raw_url:
        raw_url = input("Server URL: ").strip()
    if not raw_url:
        return 2
    if "://" not in raw_url:
        raw_url = "http://" + raw_url

    username = input("Username: ").strip()
    password = getpass.getpass("Password (not echoed, never printed): ")
    insecure = False
    if raw_url.lower().startswith("https"):
        insecure = input("Self-signed certificate? [y/N]: ").strip().lower().startswith("y")

    client = Client(raw_url, insecure)
    code, login = client.request(
        "POST", "/login", {"username": username, "password": password},
        headers={"x-return-tokens": "true"}, auth=False,
    )
    if code != 200 or not isinstance(login, dict):
        note_fail(f"login returned {code}")
        return 1
    client.token = login["user"].get("accessToken")
    say(f"{PASS}  signed in")
    say()

    # Find a book with audio.
    code, libraries = client.request("GET", "/api/libraries")
    library = next(
        (l for l in (libraries or {}).get("libraries", []) if l.get("mediaType") == "book"), None
    )
    if not library:
        note_fail("no book library")
        return 1
    code, page = client.request(
        "GET", f"/api/libraries/{library['id']}/items?limit=25&page=0&minified=1"
    )
    item = next(
        (r for r in (page or {}).get("results", []) if (r.get("media") or {}).get("numTracks")),
        None,
    )
    if not item:
        note_fail("no item with audio tracks")
        return 1
    item_id = item["id"]
    duration = float((item.get("media") or {}).get("duration") or 0)
    say(f"{INFO} using one book with audio, duration {duration:.0f}s (title withheld)")
    say()

    # ------------------------------------------------- session close ---
    say("[1] POST /api/session/:id/close  (probe 1 saw this fail)")
    play_body = {
        "deviceInfo": {"deviceId": "firelight-probe", "clientName": "Firelight probe",
                       "clientVersion": "0.1.0", "manufacturer": "Apple", "model": "probe"},
        "forceDirectPlay": True, "forceTranscode": False,
        "supportedMimeTypes": ["audio/mpeg", "audio/mp4", "audio/m4a", "audio/m4b",
                               "audio/x-m4b", "audio/aac", "audio/flac", "audio/opus"],
        "mediaPlayer": "AVPlayer",
    }

    # (a) exactly what Firelight sends today
    code, session = client.request("POST", f"/api/items/{item_id}/play", play_body)
    if code == 200 and isinstance(session, dict):
        sid = session["id"]
        code, body = client.request(
            "POST", f"/api/session/{sid}/close",
            {"currentTime": 30.0, "timeListened": 30.0, "duration": duration},
        )
        say(f"{INFO} close WITH a body            -> {code} {str(body)[:60]!r}")
        first_code = code
    else:
        note_fail(f"/play returned {code}")
        return 1

    # (b) sync first, then close — what a real listen does
    code, session = client.request("POST", f"/api/items/{item_id}/play", play_body)
    sid = session["id"]
    code_sync, _ = client.request(
        "POST", f"/api/session/{sid}/sync",
        {"currentTime": 20.0, "timeListened": 20.0, "duration": duration},
    )
    say(f"{INFO} sync before close             -> {code_sync}")
    code_close, body = client.request(
        "POST", f"/api/session/{sid}/close",
        {"currentTime": 25.0, "timeListened": 5.0, "duration": duration},
    )
    say(f"{INFO} close after a sync            -> {code_close} {str(body)[:60]!r}")

    # (c) close with no body at all
    code, session = client.request("POST", f"/api/items/{item_id}/play", play_body)
    sid = session["id"]
    code_empty, body = client.request("POST", f"/api/session/{sid}/close")
    say(f"{INFO} close with NO body            -> {code_empty} {str(body)[:60]!r}")

    if 200 in (first_code, code_close, code_empty):
        say(f"{PASS}  at least one close shape works")
    else:
        note_fail("every close shape failed — Firelight leaks an open session per book")
    say()

    # ----------------------------------------------- progress write ---
    say("[2] PATCH /api/me/progress/:id  then read it back")
    code, _ = client.request(
        "PATCH", f"/api/me/progress/{item_id}",
        {"currentTime": 123.0, "duration": duration,
         "progress": (123.0 / duration) if duration else 0.0, "isFinished": False},
    )
    say(f"{INFO} progress write -> {code}")
    if code != 200:
        note_fail("writing progress failed — this is how every position is saved")

    time.sleep(1)
    code, me = client.request("GET", "/api/me")
    entries = (me or {}).get("mediaProgress") or []
    mine = next((e for e in entries if e.get("libraryItemId") == item_id), None)
    if mine:
        say(f"{PASS}  progress read back ({len(entries)} entries total)")
        missing = [k for k in EXPECTED_PROGRESS if k not in mine]
        if missing:
            note_fail(f"mediaProgress MISSING {missing}")
        else:
            say(f"{PASS}  mediaProgress: all {len(EXPECTED_PROGRESS)} expected keys present")
        extra = [k for k in sorted(mine) if k not in EXPECTED_PROGRESS]
        if extra:
            say(f"{INFO} also present: {extra}")
        say(f"{INFO} currentTime={mine.get('currentTime')!r} progress={mine.get('progress')!r}")
        say(f"{INFO} episodeId={mine.get('episodeId')!r} (null for a book, as Firelight assumes)")
        last = mine.get("lastUpdate")
        if isinstance(last, (int, float)) and last > 10_000_000_000:
            say(f"{PASS}  lastUpdate is epoch MILLISECONDS")
        else:
            note_fail(f"lastUpdate is {last!r} — the date decoder expects epoch ms")
        say(f"{INFO} ebookLocation={mine.get('ebookLocation')!r} "
            f"ebookProgress={mine.get('ebookProgress')!r}")
    else:
        note_fail("progress did not come back from /api/me")
    say()

    # ------------------------------------------- offline local session ---
    say("[3] POST /api/session/local  (the whole offline queue depends on this)")
    now_ms = int(time.time() * 1000)
    local_session = {
        "id": "7f3b1c2e-0000-4000-8000-000000000001",
        "libraryItemId": item_id,
        "episodeId": None,
        "libraryId": library["id"],
        "displayTitle": "Firelight probe",
        "duration": duration,
        "playMethod": 0,
        "mediaPlayer": "AVPlayer",
        "deviceInfo": {"deviceId": "firelight-probe", "clientName": "Firelight probe",
                       "clientVersion": "0.1.0", "manufacturer": "Apple", "model": "probe"},
        "currentTime": 456.0,
        "timeListening": 60.0,
        "startTime": 396.0,
        "startedAt": now_ms - 60_000,
        "updatedAt": now_ms,
    }
    code, body = client.request("POST", "/api/session/local", local_session)
    say(f"{INFO} local session -> {code} {str(body)[:80]!r}")
    if code == 200:
        say(f"{PASS}  offline sessions are accepted in the shape Firelight sends")
    else:
        note_fail("offline session rejected — Phase 4's queue would never drain")

    time.sleep(1)
    code, me = client.request("GET", "/api/me")
    after = next(
        (e for e in ((me or {}).get("mediaProgress") or []) if e.get("libraryItemId") == item_id),
        None,
    )
    if after:
        say(f"{INFO} position after the offline session: {after.get('currentTime')!r}")
        if abs(float(after.get("currentTime") or 0) - 456.0) < 2:
            say(f"{PASS}  the offline session moved the server's position to its own")
        else:
            say(f"{WARN}  the offline session did not move the position "
                "— Firelight also PATCHes progress, so this is belt and braces")
    say()

    # ----------------------------------------------------- cleanup ---
    say("[4] Cleaning up what this probe wrote")
    # `DELETE /api/me/progress/:id` takes the **media progress id** — a UUID of
    # its own — not the library item id. Passing the item id 404s and silently
    # leaves the progress behind, which is what the first run of this probe did.
    progress_id = (mine or {}).get("id")
    if not progress_id:
        code, me = client.request("GET", "/api/me")
        progress_id = next(
            (e.get("id") for e in ((me or {}).get("mediaProgress") or [])
             if e.get("libraryItemId") == item_id),
            None,
        )

    if progress_id:
        code, _ = client.request("DELETE", f"/api/me/progress/{progress_id}")
        say(f"{INFO} DELETE /api/me/progress/<progressId> -> {code}")
        if code == 200:
            say(f"{PASS}  progress removed; your server is as it was")
        else:
            note_fail(f"could not remove the progress this probe wrote ({code}) "
                      "— clear it in the web UI")
    else:
        say(f"{WARN}  no progress id found to delete; clear it in the web UI if it bothers you")

    code, me = client.request("GET", "/api/me")
    still_there = any(
        e.get("libraryItemId") == item_id
        for e in ((me or {}).get("mediaProgress") or [])
    )
    say(f"{INFO} progress still present afterwards: {still_there}")
    say()

    say("=" * 64)
    if failures:
        say(f"RESULT: {failures} problem(s) found.")
    else:
        say("RESULT: the progress and offline-sync paths work as built.")
    say("=" * 64)
    return 1 if failures else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\nCancelled.")
        sys.exit(130)
