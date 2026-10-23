# Firelight architecture

## Shape

Five Xcode targets over one local Swift package of ten modules. The targets are
thin; everything testable lives in the package.

```
Firelight (iOS app) ──┐
FirelightWidgets ─────┤
FirelightShare ───────┼──► Packages/FirelightKit
FirelightWatch ───────┤
FirelightTests ───────┘
```

All four shipping targets share one App Group
(`group.com.colewilliams.firelight`) and one Keychain access group
(`$(AppIdentifierPrefix)com.colewilliams.firelight.shared`). That is the whole
reason the widgets can show what you are listening to and the watch can play it.

## Modules

| Module | Owns | Depends on |
| --- | --- | --- |
| `ABSKit` | Typed API client, auth, HTTP, Keychain, certificate pinning, server version and feature table | — |
| `Persistence` | SwiftData models and schema versions, the library cache, smart shelves, the App Group container, `SharedState` for extensions | ABSKit |
| `SyncEngine` | Progress journal, positions, conflict resolution, device identity | ABSKit, Persistence |
| `PlaybackKit` | Audio engine, playback sessions, book-time conversion, Now Playing, speed, smart rewind, sleep timer | ABSKit, SyncEngine, DesignSystem |
| `ReaderKit` | Format router, Readium and PDFKit readers, highlights | ABSKit, SyncEngine |
| `ConversionKit` | MOBI/AZW3 → EPUB, comics → PDF | ABSKit |
| `DownloadKit` | Background downloads, the download store, smart download rules, connection monitoring | ABSKit, Persistence |
| `DesignSystem` | Colour, type, spacing, motion, haptics, glass, shared views | — |
| `Features` | The SwiftUI screens, one area per file | all of the above |
| `ABSMockServer` | A URLProtocol stand-in for a real ABS server (tests only) | ABSKit |

The dependency arrows only ever point down that table. `DesignSystem` knows
nothing about Audiobookshelf; `ABSKit` knows nothing about SwiftUI.

## Data flow

```
ABS server ──HTTP──► ABSKit.ABSClient ──► SyncEngine ──► Persistence (SwiftData)
                                              │                  │
                                              ▼                  ▼
                                     ProgressJournal        Features (SwiftUI)
                                              │                  ▲
                                              └──── socket ──────┘
```

Reads are **cache-first**: a screen renders from SwiftData immediately and a
background refresh updates it. Nothing in the UI waits on the network to draw
its first frame. `LibraryController.load()` touches no network at all;
`refresh()` runs after it and writes through the same store, so the screen
updates as each library lands rather than after all of them.

Smart shelves are derived from the cache, never fetched. That is what lets the
home screen be correct on a plane.

## How sync works

Progress is the most important thing in the app, so it is the most defensive
part of it.

1. **Write locally first.** Every position change becomes a
   `ProgressJournalEntry` — position, timestamp, device id — written to disk
   *before* any network call. Nothing is lost if the app dies or the network is
   gone.
2. **Drain the queue.** Pending entries sync on pause, on chapter change, every
   15 seconds while playing, and on backgrounding. Offline sessions become ABS
   local sessions (`POST /api/session/local`) when the server returns.
3. **Resolve conflicts.** `ProgressConflictResolver` takes the local and remote
   positions and returns one of `keepLocal`, `takeRemote`, `ask` or `noChange`.
   Newest timestamp wins — *except* when applying it would move the user more
   than 2 minutes of audio or 2% of an ebook, which prompts instead. The
   threshold is symmetric: a large jump forward is as disorienting as one back.
4. **Keep the history.** Entries are not discarded after syncing; the
   per-item position history screen is built from them, and each one is
   tappable to jump back.
5. **Listen live.** The ABS socket pushes progress from other devices, which
   enters through the same resolver as everything else — there is exactly one
   code path that can move a user's position.

Implemented in `SyncEngine`: `SwiftDataJournalStore` is the table,
`ProgressSyncService` is the only writer, and `ProgressConflictResolver` is the
rule. `PlaybackController` reports positions into the journal through a
closure, so the player never talks to the network about progress directly.

## How playback works

An audiobook is usually many files, and every layer above `AudioEngine` works
in **book time** — one continuous timeline from 0 to the book's duration.
`TrackTimeline` converts book time to a file and an offset within it, using
each track's `startOffset`. The scrubber, the chapters, the sleep timer and
everything synced to the server are all in book time.

Seeking across a file boundary rebuilds the player queue from the target file
onward, so transitions between files stay gapless. `AVPlayer` resets its rate
on every item change and stall, so the speed is re-applied whenever playback
resumes.

Colours in the player come from the cover, but every one of them goes through
the WCAG check first: the background is deepened from the artwork's average,
and the text and accent are adjusted until they pass AA against it. A dark
cover can change how the player looks; it cannot make it unreadable.

## Offline

Three things make the app work with no connection, and they are separate on
purpose:

- **The library** renders from the SwiftData cache, so the shelf is there.
- **The journal** holds positions locally and queues them, so listening still
  counts and still syncs later.
- **Downloads** put the audio on disk, and `AudioEngine` plays local files
  through the same code path as streamed ones — a downloaded book is not a
  special mode.

## What syncs where

Three stores, deliberately separate:

- **The local store** (App Group container) holds the library cache, the
  progress journal, downloads and episodes. It never leaves the device.
- **The synced store** holds highlights, mirrored through the user's own
  private CloudKit database. It is the only thing the user *wrote*.
- **The Keychain** holds tokens, proxy headers and the Hardcover token, shared
  across the app and its extensions by access group.

Nothing of the user's reaches any server of ours, because there isn't one.

## Transport details that matter

- Each server has a local and a remote URL. They are raced on launch and on
  network change; the winner is remembered.
- Per-server custom headers are attached to *every* request, for Cloudflare
  Access, Authelia and friends. Per-call headers and our own `Authorization`
  win on a name collision.
- A 401 triggers exactly one refresh and one retry. A second 401 is
  `APIError.unauthorized` and the user signs in again. The auth calls
  themselves never retry, so a bad refresh cannot recurse.
- A self-signed certificate is trusted only when its SHA-256 fingerprint
  matches the one the user explicitly accepted for that host. Everything else
  falls through to the system. Validation is never disabled globally.
- The server's base sub-path is preserved when building every URL.

## Testing

`ABSMockServer` answers over `URLProtocol` on its own unique host, so tests
exercise the real `URLSessionHTTPClient` — URL building, headers, bearer
tokens, the refresh-retry path and the real decoders — rather than a stubbed
client that could not catch any of those bugs. Each mock server instance is
independent, so the suite runs in parallel.
