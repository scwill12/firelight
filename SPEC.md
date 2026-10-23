# ABS iOS Client — Master Build Spec

> Source: Cole Williams, 2026-10-21. This file is the contract. Phases are built
> one at a time, each ending at a checkpoint with a manual device test list.

## How this spec is used

1. Claude Code reads this file completely at the start of every phase.
2. It completes **only** the phase it was asked for, then stops at the checkpoint
   and prints the manual test checklist.
3. Cole tests on a real device. If a checkpoint fails, he describes what he saw
   and the failure is fixed before the next phase. A failed checkpoint is never
   skipped.
4. A fresh session starts each phase. `CLAUDE.md` and `PROGRESS.md` carry the
   context forward.

Testing requires a running Audiobookshelf server holding at least: several
audiobooks, a podcast, an EPUB, a PDF, a CBZ, a CBR, a MOBI, and an AZW3.

## Mission

Build a free, open-source, native iOS client for self-hosted Audiobookshelf
(ABS) servers. It plays audiobooks and podcasts, reads ebooks like a Kindle, and
should be the best ABS client available on any platform.

### Product principles

- **Completely free.** No paywalls, no locked features. An optional tip jar
  unlocks nothing.
- **Open source under MIT.** Every dependency must be MIT, BSD, Apache 2.0,
  MPL 2.0, or zlib. No GPL or LGPL code.
- **Privacy first.** No analytics, no ads, no crash-reporting SDKs, no accounts
  of our own. The App Store privacy label must be "Data Not Collected."
- **Offline first.** The app opens instantly from local cache and works without
  a connection. Network refreshes happen quietly in the background.
- **Native and premium.** SwiftUI, system frameworks first, smooth animations,
  haptics, full accessibility. It should feel like Apple built it.
- **Never lose the user's place.** Progress sync is the most important feature in
  the app. Treat any lost or overwritten position as a critical bug.
- **Never build a server.** All features work against a stock ABS server. Data
  ABS doesn't store goes in iCloud or on-device.

### Working rules

1. One phase at a time. Stop at its checkpoint and print the manual test
   checklist for Cole.
2. Keep three files current:
   - `CLAUDE.md` — project conventions, architecture summary, build and test
     commands, gotchas discovered.
   - `PROGRESS.md` — phases completed, what's in progress, known issues, and
     decisions made with the reason for each.
   - `ARCHITECTURE.md` — modules, data flow, and how sync works.
3. Build after every meaningful change with `xcodebuild`, for the app and every
   extension. Never end a phase with a broken build or newly introduced warnings.
4. Write unit tests for the API client, sync engine, progress conflict
   resolution, download manager, format detection, and every converter. Run them
   before each checkpoint.
5. Verify the ABS API from source, don't guess. Check endpoints and payloads
   against the `advplyr/audiobookshelf` GitHub repo (especially
   `server/routers/ApiRouter.js` and the controllers) and the official API docs.
   Record anything surprising in `CLAUDE.md`.
6. Ask before adding any dependency not on the approved list. State its license.
7. Never log or display tokens, passwords, or full server URLs in logs,
   diagnostics, or error messages.
8. Use feature flags for anything that depends on a newer ABS version or newer
   iOS version. Degrade gracefully with a clear message, never a crash or silent
   failure.
9. No placeholder UI at checkpoints. Every screen that ships in a phase has real
   empty, loading, offline, and error states.

## Tech stack and architecture

Swift 6 with strict concurrency, SwiftUI, Observation, and SwiftData. Minimum
iOS 18.0. Adopt the iOS 26 design language (Liquid Glass) where available, with
clean fallbacks on iOS 18. watchOS 11 minimum for the Watch app.

### Approved dependencies

| Package | Use | License |
| --- | --- | --- |
| Readium Swift Toolkit | EPUB and CBZ reading, TTS, locators | BSD-3 |
| ZIPFoundation | Reading and writing ZIP/EPUB/CBZ archives | MIT |
| Nuke | Cover image loading and caching | MIT |
| Socket.IO-Client-Swift | ABS real-time socket connection | MIT |
| foliate-js (bundled JS) | Parsing MOBI/AZW3 for conversion only | MIT |
| JSZip (bundled JS, MIT option) | Writing EPUB packages from the converter | MIT |

Apple frameworks to use instead of third-party code: AVFoundation,
MediaPlayer, PDFKit, StoreKit 2, ActivityKit, WidgetKit, App Intents, CarPlay,
CoreSpotlight, CloudKit, AuthenticationServices, MessageUI, FoundationModels,
BackgroundTasks, Network, Security (Keychain).

**Needs Cole's approval before use:** UnrarKit for CBR support. Its wrapper is
BSD, but it bundles the UnRAR source, which has its own freeware license.
Explain the license to Cole and get a yes before adding it.

### Targets

- `[AppName]` — the iOS/iPadOS app, also runs on Apple silicon Macs.
- `[AppName]Widgets` — home and lock screen widgets plus the Live Activity.
- `[AppName]Share` — share extension for uploading files to ABS.
- `[AppName]Watch` — watchOS app with offline playback.
- `[AppName]Tests` — unit tests.

All targets share data through one App Group. Credentials live in a shared
Keychain access group.

### Module layout

Core logic lives in local Swift packages so extensions can reuse it:

- **ABSKit** — typed API client, auth, token refresh, server version detection,
  socket client. No UI.
- **Persistence** — SwiftData models and the local cache of libraries, items,
  and progress.
- **SyncEngine** — progress journal, offline queue, conflict resolution,
  position history, iCloud sync.
- **PlaybackKit** — audio engine, sessions, Now Playing, sleep timer, smart
  rewind.
- **ReaderKit** — format router, Readium and PDFKit readers, highlights,
  typography settings.
- **ConversionKit** — MOBI/AZW3 to EPUB, comics to PDF.
- **DownloadKit** — background downloads and smart download rules.
- **DesignSystem** — colors, type, spacing, haptics, dynamic cover color, shared
  components.
- **Features** — the SwiftUI screens, one folder per feature.

Use dependency injection for every service so tests can run against a mock ABS
server.

## Audiobookshelf API notes

The endpoints below are starting points. Confirm each one's method, path, and
payload against the current ABS source before writing code for it, and record
any differences in `CLAUDE.md`.

| Area | Endpoints to verify |
| --- | --- |
| Server info | `GET /status`, `GET /ping` (server version, auth methods available) |
| Auth | `POST /login`; newer ABS versions add access and refresh tokens, so support both the legacy token and refresh flow; OpenID Connect login flow |
| Libraries | `GET /api/libraries`, `GET /api/libraries/:id/items` (paging, sort, filter), `/series`, `/collections`, `/personalized` shelves, `/search` |
| Items | `GET /api/items/:id?expanded=1`, cover endpoint, ebook file endpoint, `PATCH /api/items/:id/media` for metadata edits |
| Playback | `POST /api/items/:id/play` to open a session, `POST /api/session/:id/sync`, `POST /api/session/:id/close`, local session sync for offline listening |
| Progress | `GET /api/me`, `PATCH /api/me/progress/:id` (audio position, ebook location, ebook progress, finished flag), bookmarks under `/api/me/item/:id/bookmark` |
| Podcasts | Episode lists, download-to-server triggers, episode progress (progress IDs include the episode ID) |
| Admin | Library scan, item match, chapter lookup, users, sessions, upload (`POST /api/upload`) |
| Real-time | Socket.IO connection authenticated with the user token; listen for progress updates and item added, updated, or removed events |

### Rules for the API layer

- Every request carries the user's per-server custom headers (for Cloudflare
  Access, Authelia, Authentik, and similar).
- Each server can have a local URL and a remote URL. Pick the reachable one
  automatically (see the connection feature).
- Support self-signed certificates only when the user explicitly trusts that
  server's certificate. Pin the trusted certificate per server; never disable
  validation globally.
- Detect the server version on connect. Store a feature table that maps features
  to the minimum ABS version that supports them.
- Test against the current ABS release and the release before it.

## Feature specification

Every feature below ships. The phased plan says when.

### Connection and accounts

- Onboarding: enter a server URL, see a live connection check (reachable, ABS
  version, auth methods), then log in with username and password or OpenID
  Connect through `ASWebAuthenticationSession`.
- Home/away switching: each server stores an optional local URL and a remote
  URL. On launch and on network change, probe both and use the fastest reachable
  one. Show which is active in Settings.
- Per-server custom HTTP headers, entered as name/value pairs, stored in the
  Keychain.
- Per-server trust for a self-signed certificate, with the certificate
  fingerprint shown before the user accepts.
- Multiple servers and multiple users per server, with fast switching from the
  profile menu.
- Server version warning when a feature needs a newer ABS than the user runs.

### Library

- Home screen built around Continue: the current item large and front and
  center, then recently played, then smart shelves.
- Smart shelves: Next in series, Unfinished series, Recently added, Abandoned
  (started, untouched 30+ days), Short listens (under 5 hours), and a Pick
  something for me shuffle button.
- Browse by library, author, narrator, series, collection, and genre. Cover grid
  and list views.
- Series shown as stacked covers; the series view lists books in series order
  with progress for each.
- Fast search across titles, authors, narrators, and series, with results from
  the local cache first.
- Library renders instantly from cache and refreshes in the background.
- Index downloaded items in Spotlight with title, author, and cover.

### Audio player

- Cover-to-player transition: the tapped cover lifts and expands into the player
  with a matched-geometry animation, and reverses on dismiss.
- Dynamic color: extract dominant colors from the cover and tint the player
  background, scrubber, and controls. Ensure text contrast meets WCAG AA.
- Chapter-aware scrubber showing position within the chapter, chapter marks, and
  total book progress.
- Skip back and forward with user-set intervals; chapter previous/next.
- Smart rewind after a pause: a few seconds after a short pause, more after a
  long one. Configurable.
- Speed from 0.5× to 3.5× in 0.05× steps, remembered per book.
- Sleep timer: fixed durations, end of chapter, gentle volume fade over the last
  30 seconds, and shake-to-extend.
- Bookmarks with optional notes, synced to ABS.
- Lock screen and Control Center controls with chapter titles and artwork.
- Live Activity and Dynamic Island showing cover, chapter, time remaining, and
  play/pause and skip buttons.
- CarPlay audio app: Continue, Library, Downloads, and Podcasts tabs.
- AirPlay and Bluetooth route handling; pause on headphone disconnect.
- Haptics on chapter change, scrubbing past chapter marks, and sleep timer
  ending.

### Progress sync (top priority)

- Progress journal: every position change is written locally with a timestamp
  and device ID before any network call.
- Offline listening and reading create local sessions that sync automatically
  when the server is reachable again.
- Conflict resolution: newest timestamp wins; never move a user backward without
  asking if the jump is large (over 2 minutes of audio or 2% of an ebook). Show
  a choice: "Continue from 3:42:10 on iPad, or stay at 3:20:05?"
- Position history screen per item listing recent positions by device and time,
  each one tappable to jump there.
- Live sync through the ABS socket so progress from other devices appears
  immediately.
- Sync on pause, on chapter change, every 15 seconds while playing, and when the
  app goes to the background.

### Downloads

- Background `URLSession` downloads that survive app suspension, with pause and
  resume.
- Wi-Fi only option (default on).
- Smart downloads: automatically download the next book in a series when the
  current one is 80% done, and remove finished items after a user-set number of
  days.
- Storage screen: total used, per-item size, sort by size, swipe to delete.

### Reader

Format router chooses the viewer by file type:

| Format | Viewer |
| --- | --- |
| EPUB | Readium |
| PDF | PDFKit |
| CBZ | Readium |
| CBR | Extracted with UnrarKit, shown in the comic pager |
| MOBI, AZW3 | Converted to EPUB on first open, then Readium |

- Typography: font, size, line spacing, margins, justification, hyphenation.
  Bundle Literata, Atkinson Hyperlegible, and OpenDyslexic (check each font's
  license; all three are OFL).
- Themes: white, sepia, gray, true black, and match system.
- Page turns: slide, curl, or vertical scroll.
- Dictionary lookup with `UIReferenceLibraryViewController`.
- Highlights in four colors, with notes; a highlights list per book; export
  highlights to Markdown.
- Time left in chapter and book based on the user's measured reading speed.
- Read aloud with Readium TTS and system voices for any EPUB.
- iPad landscape shows two pages side by side.
- Ebook progress syncs to ABS: for EPUB, store the Readium locator and the
  percentage; for PDF and comics, store the page number.

### Formats, conversion, and export

- MOBI/AZW3 to EPUB converter: run foliate-js in a hidden `WKWebView` to parse
  the book, write an EPUB with JSZip, validate it, and cache it. Show progress
  during conversion. Detect DRM and show "This file is DRM-protected and can't
  be opened."
- Comics to PDF: combine CBZ/CBR page images into a PDF with
  `UIGraphicsPDFRenderer` for export.
- Export from any item: original file, converted EPUB, or comic PDF, through the
  share sheet.
- Send to Kindle: user saves their `@kindle.com` address once; the button opens a
  pre-filled mail compose sheet with the EPUB or PDF attached. Show a one-time
  note about adding their email to Amazon's approved sender list. Files over
  50 MB get a message pointing to the share sheet instead. Grey out the button
  for formats Kindle doesn't accept.
- Upload converted EPUB to server (users with upload permission only), with
  confirmation.

### Podcasts

- Podcast libraries with show pages, episode lists, played/unplayed, and
  per-episode progress.
- Auto-download new episodes per show (off by default).
- Up Next queue that can mix podcast episodes and books.

### Server admin tools (admin users only)

- Trigger a library scan; see scan status.
- Match metadata for an item, edit title, author, narrator, series, description,
  and cover; chapter lookup and chapter editing.
- View users, their permissions, and active listening sessions; see server
  version and status.
- Share extension: "Add to Audiobookshelf" uploads files from Files, Safari, or
  Mail to a chosen library and folder.

### Family and kids

- Quick switching between household users on the same server.
- Kids mode: a simplified, big-cover view limited to one user's library, with no
  settings or admin access. Exiting requires Face ID, Touch ID, or the device
  passcode.

### Stats

- Listening and reading time per day, week, month, and year; streaks; books
  finished.
- Year in Books: an animated recap available in December, with shareable image
  cards rendered on-device.

### iCloud sync and integrations

- CloudKit private database syncs highlights, notes, reader settings, reading
  stats, and app preferences across the user's devices. No data leaves Apple's
  private iCloud.
- Hardcover integration: user pastes their Hardcover API token; the app marks
  books as Reading and Finished. Verify Hardcover's current GraphQL API before
  building.

### On-device intelligence

- Catch me up: for an ebook, summarize the text from the last few chapters up to
  the user's current position using Apple's FoundationModels framework. Never
  include text past the current position. Chunk long text to fit the model's
  context window. Hide the feature on devices without Apple Intelligence.

### Read-along (Storyteller)

- When an EPUB contains EPUB 3 media overlays (as produced by Storyteller),
  offer synced read-along: highlight the current sentence while the audio plays,
  and let the user switch between reading and listening at the same spot. Check
  Readium's media overlay support first; if it's missing, parse the SMIL files in
  ReaderKit.

### System integration

- Home and lock screen widgets: Continue listening, current book progress,
  reading streak.
- App Intents: Resume, Pause, Set sleep timer, Play [book title], and Add
  bookmark, usable from Siri and Shortcuts.
- Handoff between iPhone, iPad, and Mac for the current item.
- Apple Watch: Now Playing controls, plus downloading books to the watch for
  phone-free offline playback.

### Tip jar, polish, and community

- Tip jar in Settings: four StoreKit 2 consumable tips (Coffee $0.99, Snack
  $2.99, Lunch $4.99, Dinner $9.99) and a thank-you screen. Tips unlock nothing.
- Alternate app icons, free for everyone.
- Full Dynamic Type, VoiceOver labels and actions, Reduce Motion, and Increase
  Contrast support.
- What's New sheet after updates.
- Diagnostics export: user-initiated, scrubbed of URLs, tokens, and usernames,
  shared through the share sheet.
- Localization-ready from day one: every string in a String Catalog, with no
  hardcoded user-facing text.

## Phased build plan

Twenty phases. Phases 0–8 are the v1 that goes to TestFlight; 9–19 follow as
updates. At every checkpoint: the build is clean, all tests pass, `PROGRESS.md`
is updated, and the device test list is printed for Cole, then stop.

### v1 (TestFlight)

**Phase 0 — Foundation.** Xcode project, all targets, App Group, Keychain group,
local packages, DesignSystem tokens, String Catalog, `CLAUDE.md`, `PROGRESS.md`,
`ARCHITECTURE.md`, a mock ABS server for tests, and a `scripts/build.sh` that
builds and tests everything.
- Cole tests: app launches on device to a styled empty screen; widget and share
  extension appear in the system.

**Phase 1 — Connection and accounts.** Onboarding, login, OIDC, local/remote URL
switching, custom headers, self-signed trust, multiple servers and users,
version detection.
- Cole tests: log in at home, turn off Wi-Fi, confirm it switches to the remote
  URL; log in through a proxy that needs custom headers.

**Phase 2 — Library.** Home with Continue and smart shelves, browsing, series
stacks, search, cache-first loading, Spotlight indexing.
- Cole tests: library loads instantly on second launch in airplane mode; search
  finds a book by narrator.

**Phase 3 — Audio player.** Streaming playback, sessions, chapter scrubber, speed
per book, smart rewind, sleep timer, bookmarks, lock screen controls,
cover-to-player transition, dynamic color, haptics.
- Cole tests: listen 10 minutes, lock the phone, control from the lock screen,
  set end-of-chapter sleep timer.

**Phase 4 — Progress sync engine.** Journal, offline sessions, conflict
resolution with the jump prompt, position history, live socket sync.
- Cole tests: listen offline on the phone, listen online on the web, reconnect
  the phone, and confirm the prompt and correct position.

**Phase 5 — Downloads.** Background downloads, Wi-Fi only, smart downloads,
storage screen.
- Cole tests: download a large book, background the app, confirm it finishes;
  play it in airplane mode.

**Phase 6 — Reader: EPUB and PDF.** Format router, Readium, PDFKit, typography,
themes, page turns, dictionary, highlights and Markdown export, time left, read
aloud, ebook progress sync.
- Cole tests: read 10 pages, switch themes and fonts, highlight a passage, export
  highlights, check progress on the web.

**Phase 7 — Export and Send to Kindle.** Share sheet export and the Send to
Kindle flow with all its limits.
- Cole tests: send an EPUB to his Kindle address and confirm it arrives on a
  Kindle device or app.

**Phase 8 — Tip jar, accessibility, and launch polish.** StoreKit 2 tips with a
StoreKit configuration file for testing, alternate icons, full accessibility
pass, empty/error/offline states everywhere, diagnostics export, privacy
manifest.
- Cole tests: buy a tip in the sandbox; navigate the main flows with VoiceOver;
  set the largest Dynamic Type size and check nothing clips.

### Updates after v1

**Phase 9 — System integration.** Live Activity, Dynamic Island, widgets, App
Intents and Siri, Handoff.

**Phase 10 — CarPlay.** Requires Cole's CarPlay entitlement first.

**Phase 11 — Podcasts.** Show pages, episodes, auto-download, Up Next queue.

**Phase 12 — Comics.** CBZ through Readium, CBR (after license approval), comic
pager, comics to PDF export.

**Phase 13 — MOBI/AZW3 converter.** foliate-js and JSZip pipeline, DRM
detection, caching, upload converted EPUB to server.

**Phase 14 — iPad and Mac.** Sidebar layout, two-page reader, keyboard
shortcuts, Mac window sizing.

**Phase 15 — Admin tools and share extension upload.**

**Phase 16 — Family and kids mode.**

**Phase 17 — Stats, Year in Books, iCloud sync, and Hardcover.**

**Phase 18 — Catch me up and Storyteller read-along.**

**Phase 19 — Apple Watch app with offline playback,** then a release-prep pass:
README, LICENSE (MIT), CONTRIBUTING, issue and discussion templates, Weblate
setup for translations, App Store screenshots plan.

Each update phase ends with its own checkpoint in the same format: what to test
on a device, written specifically for that phase's features.

## Quality bar

### Definition of done for every feature

- Works offline or explains clearly why it can't.
- Has real loading, empty, error, and offline states.
- Supports Dynamic Type up to the largest accessibility size, VoiceOver, Reduce
  Motion, and dark mode.
- Runs at 60 fps on an iPhone 12-class device; no main-thread network or disk
  work.
- Covered by unit tests where it touches API, sync, downloads, or conversion.
- Never loses or overwrites a user's position without asking.
- Every user-facing string is in the String Catalog.

### Things Claude Code cannot do — Cole handles these

- [ ] Apple Developer Program membership ($99/year)
- [ ] Create the App ID, App Group, iCloud container, and Keychain group in the
      developer portal when Phase 0 asks for them
- [ ] Request the CarPlay audio app entitlement from Apple early, since approval
      can take weeks
- [ ] Create the four tip products in App Store Connect with matching product IDs
- [ ] Set up a test ABS server with sample files in every format, plus a podcast
      and a second user account
- [ ] Approve or reject UnrarKit after reading its license summary
- [ ] Choose the final app name and check it's available on the App Store
- [ ] Create the GitHub repo, enable Discussions, and set up TestFlight public
      beta
- [ ] Generate a Hardcover API token for testing Phase 17
