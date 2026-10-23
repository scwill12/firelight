# Progress

## Where we are

**Every phase is implemented except the watch app, which Cole dropped.** The app, widgets and
share extension build clean with no warnings we introduced, and 307 unit tests
pass across 59 suites. The app installs and launches on a simulator, and the
API has been verified against a live 2.37.1 server.
The watch target is written but cannot be compiled on this machine (see
Blocked).

Phases 1–9 are *code*-complete. The API they talk to is now verified
against a real server; what remains unverified is the device behaviour, because there isn't one to verify against. Their
checkpoints are unmet until there is. What has been verified on a simulator:
the app launches, onboarding renders, and the live connection check correctly
reports an unreachable address.

Phase 19's watch app is **deliberately not built** — Cole dropped it on
2026-10-22. The rest of Phase 19 (README, CONTRIBUTING, issue templates,
Weblate configuration, screenshots plan) is done.

| Phase | State |
| --- | --- |
| 0 — Foundation | ✅ Complete, build green, tests green |
| 1 — Connection and accounts | ⚠️ Code complete, build and tests green, **unverified against a real server** |
| 2 — Library | ⚠️ Code complete, build and tests green, **unverified against a real server** |
| 3 — Audio player | ⚠️ Code complete, build and tests green, **no audio has ever been played** |
| 4 — Progress sync engine | ⚠️ Code complete, build and tests green, **never run against a real server or a second device** |
| 5 — Downloads | ⚠️ Code complete, build and tests green, **no file has ever been downloaded** |
| 6 — Reader: EPUB and PDF | ⚠️ Mostly complete — see the gaps below. Build and tests green, **no book has ever been opened** |
| 7 — Export and Send to Kindle | ⚠️ Code complete, build and tests green, **nothing has been emailed** |
| 8 — Tip jar, accessibility, polish | ⚠️ Code complete, build and tests green, **no purchase has been made** |
| 9–19 — updates after v1 | Not started |

## What Phase 0 shipped

- Five targets wired through one App Group and one shared Keychain group.
- Ten-module Swift package with a real, tested API layer: typed client, HTTP
  stack with per-server custom headers, bearer auth with one-shot refresh
  retry, certificate pinning, server version detection and a feature table.
- The progress conflict resolver — the spec's top-priority invariant — fully
  implemented and covered by 13 tests, ahead of the sync engine that will use it.
- Ebook format detection by magic bytes with extension tie-breaking.
- Design system: colour, type, spacing, motion, haptics, Liquid Glass with an
  iOS 18 fallback, WCAG contrast maths, and real loading/empty/error/offline
  state views.
- A URLProtocol-backed mock ABS server so tests exercise the production stack.
- An app icon generated from a committed script, seven String Catalogs, and a
  Settings screen that self-checks the App Group, the Keychain and the database
  on a real device.

## What Phase 1 shipped

- Onboarding with a live connection check that debounces as you type and
  reports version, available auth methods, and whether SSO is on.
- Password sign-in, and OpenID Connect through `ASWebAuthenticationSession`
  with PKCE.
- Home/away address switching: both addresses are probed concurrently and the
  local one wins whenever it answers. Settings shows which is in use.
- Per-server custom HTTP headers, editable before the first connection (a
  proxied server will not answer `/status` without them) and stored in the
  Keychain.
- Self-signed certificate trust, shown as a SHA-256 fingerprint the user
  confirms before trusting, pinned per host.
- Multiple servers and multiple accounts per server, with switching and
  sign-out that invalidates the refresh token server-side first.
- Token storage with one-shot refresh on 401, and concurrent refreshes
  coalesced into one call.

## What Phase 2 shipped

- A cached library in SwiftData (schema v2, lightweight migration from v1) that
  renders before any network call and refreshes quietly behind it.
- Home built around Continue, with smart shelves computed locally: Recently
  played, Next in series, Unfinished series, Recently added, Picked up then put
  down, and Short listens — plus "Pick something for me".
- Browse as a grid or a list, sorted by title, author, date added, length or
  progress, and grouped by author, narrator, series or genre. A series reads in
  series order with each book's number and progress.
- Search across title, author, narrator, series and genre, answered from the
  cache first so it works offline, falling back to the server only when the
  cache has little to offer.
- Covers loaded and disk-cached through Nuke, authenticated by header.
- Spotlight indexing of the cached library.

## What Phase 3 shipped

- Playback over AVFoundation that speaks in *book* time: a book split across
  60 files behaves as one timeline, with each track's `startOffset` folded in.
- Chapter-aware scrubber with chapter marks, a haptic as each passes under the
  thumb, and chapter previous/next that restarts the current chapter unless you
  have only just entered it.
- Speed from 0.5× to 3.5× in 0.05 steps, remembered per book.
- Smart rewind on resume, scaled to how long you were away.
- Sleep timer: fixed durations, end of chapter (which accounts for playback
  speed), a 30-second volume fade, and shake-to-extend.
- Bookmarks with notes, synced to ABS.
- Lock screen, Control Center and AirPods controls, with the chapter as the
  title and the book as the album.
- A player tinted from the cover, with every colour contrast-checked first, and
  a mini player above the tab bar.

## What Phase 4 shipped

- A durable progress journal in SwiftData (schema v3). Every position is
  written locally, with a timestamp and a device id, **before** any network
  call — so a tunnel, a crash or a flat battery cannot lose a place.
- An offline queue that groups a stretch of listening into one ABS local
  session rather than hundreds of writes, and drains when the server returns.
- Conflict resolution through the Phase 0 resolver, with a prompt that names
  both positions and the device each came from, and no default answer.
- A per-item position history, newest first, each entry tappable to jump
  there, with unsynced entries marked as such.
- Live sync over Socket.IO, so another device's progress arrives at once.

## What Phase 5 shipped

- Background `URLSession` downloads that survive app suspension, writing into
  the shared App Group container so the system can hand work back after the app
  has been killed.
- Wi-Fi only, on by default, enforced against the live connection rather than
  the session's own flag.
- Smart downloads: fetch the next book in a series at 80%, and remove finished
  books after a configurable number of days. Both off by default.
- A storage screen: total used, per-item sizes, sort by size or title, swipe
  to delete.
- Offline playback — a downloaded book plays from disk through exactly the same
  engine path as a streamed one, and knows where it was from the journal rather
  than from the server.

## What Phase 6 shipped

- A format router that trusts the file's bytes over its extension, sending
  EPUB to Readium and PDF to PDFKit.
- Typography: typeface, size, line spacing, margins, justification and
  hyphenation, mapped onto Readium's own preferences.
- Themes (white, sepia, grey, true black, match system) and page turns (slide,
  curl, continuous scroll).
- Highlights in four colours with notes, and Markdown export that groups by
  chapter and orders by position.
- Dictionary lookup through `UIReferenceLibraryViewController`.
- Time left, from the reader's own measured pace — and nothing at all until
  there is enough evidence to be honest about it.
- Ebook progress synced to ABS: a Readium locator for EPUB, a page number for
  PDF, through the same journal as audio.

### Not done in Phase 6

- **The three bundled fonts are not bundled.** Literata, Atkinson Hyperlegible
  and OpenDyslexic are offered in the picker but their files are not in the
  repo, so choosing one currently falls back to the system face. The files are
  OFL; they need adding to the app target and registering in the Info.plist.
- **Read aloud (Readium TTS) is not implemented.**
- **Highlighting from an EPUB selection is not wired.** The callback exists but
  Readium's selection delegate is not connected, so highlights can currently be
  made from a PDF selection only.

## What Phases 7 and 8 shipped

- Export through the share sheet, and Send to Kindle through a pre-filled mail
  compose sheet — with every one of Amazon's limits checked *before* the sheet
  opens: accepted formats, the 50 MB ceiling, a valid `@kindle.com` address,
  and a one-time warning about the approved-sender list.
- A StoreKit 2 tip jar: four consumables, a `.storekit` configuration so it can
  be exercised without App Store Connect, and a thank-you screen. Tips unlock
  nothing, and the screen says so.
- Three app icons (Ember, Hearth, Moonlight), all free, all generated from the
  committed script.
- A diagnostics export carrying counts and versions and **no** address,
  username or token — with a test that tries to find one.
- A privacy manifest declaring no tracking and no collected data, with the
  required-reason API declarations the App Store needs.

## What Phase 9 shipped

- A `NowPlayingSnapshot` in the shared container that the app writes and the
  extensions read, so a widget never opens the database.
- A Live Activity and Dynamic Island with cover-less but complete chrome:
  chapter, progress, a self-counting time remaining, and working play/pause and
  skip buttons.
- Home screen widgets (Continue, Streak) and lock-screen accessory widgets in
  all three shapes.
- App Intents — Resume, Pause, Skip, Set sleep timer, Add bookmark — with Siri
  phrases, surfaced through `AppShortcutsProvider`.
- Handoff between devices, refusing any payload it cannot fully understand.

## What Phases 10–12 shipped

**CarPlay** — a tab bar of Continue, Library, Downloads and Podcasts, with the
Now Playing template. The scene is declared alongside the normal window scene,
so the app is unaffected when the entitlement is absent (verified: it still
launches). **Dormant in v1** — the entitlement is deliberately not in the
build; see "CarPlay is deferred past v1" below.

**Podcasts** — show pages with every episode, played/unplayed/in-progress
filtering, per-episode progress, the server's own auto-download toggle, a
check-for-new-episodes action, and an Up Next queue that mixes books and
episodes.

**Comics** — CBZ reading through a pager of our own, with natural-order page
sorting, a three-page memory window, and comic-to-PDF export that preserves
each page's dimensions.

## What Phases 13–19 shipped

**MOBI/AZW3** — foliate-js and JSZip vendored and run in a hidden WKWebView,
producing a validated EPUB that is cached so the conversion happens once. DRM
is detected in Swift from the PalmDOC header before the web view is even
created.

**iPad and Mac** — a sidebar on regular widths, tabs on compact, and keyboard
shortcuts for playback.

**Admin and upload** — library scans, running jobs, users, live sessions, and a
share extension that really uploads, building its client from the shared
container and shared Keychain.

**Kids mode** — a big-cover library with nothing else, which only Face ID,
Touch ID or the passcode can leave. It fails closed on any error.

**Stats, iCloud, Hardcover** — listening time measured from the journal by how
far the book moved, a December Year in Books with an on-device share card,
highlights syncing through the user's private iCloud database, and an optional
Hardcover connection.

**Catch me up and read-along** — on-device summarisation through
FoundationModels, and SMIL media-overlay parsing for Storyteller books.

**Release prep** — README with the full licence table, CONTRIBUTING, issue
templates, Weblate configuration, and a screenshots plan.

## Decisions, and why

**Only highlights sync through iCloud.** They are the only thing in the app the
user *wrote*; everything else is a cache of the server or can be rebuilt from
it. Syncing a library cache would be slow, pointless, and would put someone's
reading habits in a place they did not ask for.

**CloudKit forced three changes, each caught at runtime rather than compile
time.** It does not support unique constraints, so `HighlightRecord` lost its
`@Attribute(.unique)`. It requires every attribute to be optional or defaulted,
so all of them gained defaults. And `cloudKitDatabase` defaults to
`.automatic`, which silently switched CloudKit on for **every in-memory store**
the moment the entitlement was added — including the library cache, which
CloudKit refuses outright, so the app failed to open its database at all. Every
non-synced configuration now says `.none` explicitly.

**DRM is detected in Swift, not JavaScript.** The encryption flag is twelve
bytes into the PalmDOC header. Finding out a book is locked *after* spinning up
a web view and parsing forty megabytes is a poor way to learn it.

**Catch me up cuts the text before the model sees it.** A summary that spoils
the next chapter is worse than no summary, so the truncation happens in Swift,
is covered by tests, and the model is never given text past the reader's
position.

**Podcasts get their own model, not the book one.** A podcast's metadata uses
`author`, a book's uses `authorName`. Decoding a podcast with the book model
does not fail — it silently loses the author, which is exactly the kind of bug
that survives to release. `ABSPodcastItem` exists to make that impossible.

**Comics use Firelight's own pager, not Readium's navigator.** Readium adds
nothing for a bag of images, and one pager means CBZ and CBR behave
identically once CBR is possible. Page ordering is natural-sorted, because
plain string sorting puts `page10` before `page9` and silently shuffles every
comic longer than nine pages.

**Comic pages are loaded three at a time.** A comic page is a multi-megabyte
image; holding four hundred in memory is how a reader gets killed by the
system.

**No ZIPFoundation dependency.** The upstream package and Readium's fork share
a SwiftPM identity, so resolving both is impossible. Readium's own archive
layer already opens the file, so comics use that and the dependency list stays
shorter.

**One package with ten modules, not ten packages.** The spec asks for "local
Swift packages". Separate packages would mean ten manifests and ten copies of
every external pin for the same module boundaries. One package gives the same
`import ABSKit` boundaries and the same enforced dependency graph with a tenth
of the ceremony.

**No external dependencies yet.** Readium, Nuke, Socket.IO and ZIPFoundation
are all approved, but none is needed to build a foundation, and Readium in
particular is a large resolve. Each arrives in the phase that uses it, keeping
the Phase 0 build fast and its failures legible.

**The watch app is not embedded in the iOS app.** It will be in Phase 19, when
there is something to run on it. Embedding it now would force watch
provisioning onto every device install for no benefit.

**No iCloud entitlement yet.** CloudKit sync is Phase 17. Adding the container
now would mean portal setup for a capability nothing uses.

**The conflict prompt threshold is symmetric.** The spec says "never move a
user backward without asking if the jump is large", but its own example prompt
("Continue from 3:42:10 on iPad, or stay at 3:20:05?") is a jump *forward*. A
22-minute leap forward loses your place exactly as badly as one back, so the
resolver asks whenever the move exceeds the threshold in either direction, and
applies small differences silently as ordinary sync lag.

**Tests live in the app test target, not per-module test targets.** One
`xcodebuild test` runs everything on a simulator, including the UIKit-dependent
modules that `swift test` on macOS could not build at all.

**The share extension tells the truth.** It can't upload until Phase 15, so it
says so rather than showing a form that goes nowhere. Same for the widget's
not-configured state.

**The Live Activity counts down by itself.** `Text(timerInterval:)` renders a
live countdown from a finish time, so the app pushes an update on real events
rather than once a second. A Live Activity that needs a push per second gets
throttled into uselessness.

**Widgets project the position forward.** A widget redraws on the system's
schedule, not the app's, so a snapshot carries `updatedAt` and advances itself
while playing. Without that the progress bar would sit frozen wherever the app
last wrote it.

**`PlaybackIntentBridge` is the one singleton in the project.** App Intents are
built by the system with nothing to inject into, so there is no other way for
one to reach the running player. It is a weak reference, registered at launch,
and an intent that finds nothing says so rather than silently doing nothing.

**Kindle's limits are checked before the compose sheet opens.** Every one of
them — wrong format, oversized file, unapproved sender — fails *silently* at
Amazon's end, which is indistinguishable from the app being broken. Refusing
up front with a reason is the only honest behaviour.

**The diagnostics report is built from counts, not objects.** Passing the
session in would make it one careless line away from leaking an address. It
takes integers and booleans, and a test asserts no secret survives.

**Time left says nothing until it knows something.** A fixed words-per-minute
figure is wrong for almost everyone, so the estimator measures the reader's own
pace, discards gaps longer than five minutes as "put the book down", rejects
implausible speeds, and returns `nil` until it has real evidence. The UI says
"Time left appears as you read" rather than inventing a number.

**A PDF's position is a bare page number.** ABS stores `ebookLocation` as an
opaque string, and another client reading `42` can act on it. Wrapping it in
JSON would make it ours alone.

**The engine takes resolved tracks, not a session.** Streaming and offline
playback differ only in where the URLs come from, so `AudioEngine` was
refactored to accept `[ResolvedTrack]` and the session becomes one of two ways
to produce them. One playback path means offline cannot quietly behave
differently.

**A half-downloaded book offers no local tracks.** Playing what has arrived so
far would stop mid-sentence and look like a bug. It streams until it is whole.

**Automatic downloads fetch exactly one book ahead.** Downloading a series on
someone's behalf is how you fill their phone; one book is help, ten is a
problem.

**A remote position can only move the user through the resolver.** The socket,
the `/api/me` reconciliation and the conflict prompt all funnel into
`ProgressSyncService.receiveRemote`. One code path means one place to get the
most important rule in the app right.

**Entries are kept after syncing, not deleted.** They are the position history,
which is what makes a bad sync recoverable by the user rather than only by us.
Pruning keeps the newest 40 per item and will not touch anything still pending.

**Only one conflict prompt at a time.** Reconciling a whole library could
produce dozens; being asked thirty questions on launch is not a feature. The
rest wait until the first is answered.

**Media URLs carry `?token=`; covers do not.** `AVPlayer` cannot set an
`Authorization` header through public API, and ABS accepts a token in the query
string. Covers go through `URLSession`, which can, so they use a header. The
inconsistency is deliberate: it is the smallest surface that still works.
`Redaction.url` drops query strings, so a media token cannot reach a log.

**The sleep timer's "end of chapter" divides by the playback rate.** Ten
minutes of chapter left at 2× is five minutes of sleep. Showing chapter time
when the user asked how long until it stops would be wrong by half.

**Extending an end-of-chapter timer converts it to a fixed one.** "One more
chapter" and "give me a bit longer" are different requests, and a shake is the
second one.

**Smart shelves are computed locally, not fetched.** ABS has a
`/personalized` endpoint, but its shelf shape is unverified and, more
importantly, a server round trip cannot produce a shelf on a plane. The spec's
shelves are all derivable from the cache, so they are — which makes them
instant and offline by construction.

**Covers authenticate by header, not by `?token=`.** ABS accepts a token in the
query string, and it would be easier. It would also write the token into every
image cache key, every disk cache filename and every proxy log, which working
rule 7 forbids.

**Search matches one denormalised field.** A `#Predicate` ORing five
`localizedStandardContains` calls defeats the Swift type checker outright. One
lowercased, diacritic-folded `searchText` column is simpler, faster, and is why
"bronte" finds "Brontë".

**The prompt threshold is symmetric** — see the conflict resolver decision
below. **Concurrent refreshes are coalesced.** ABS rotates the refresh token on every
use. Two simultaneous 401s would otherwise start two refreshes, and the second
would present a token the server had just retired — signing the user out for no
reason. `AuthStore` shares one in-flight refresh between all callers.

**Custom headers are editable before a server is added.** A server behind
Cloudflare Access will not answer `/status` at all without them, so collecting
them only after a successful connection would make those servers impossible to
add. Draft headers live in memory during onboarding and move to the Keychain
once the server record exists.

**The OIDC redirect URI is `firelight://oauth`.** ABS matches mobile redirect
URIs exactly — there is no pattern matching — so this exact string has to be in
the server's auth settings. The onboarding screen says so next to the SSO
button rather than letting it fail mysteriously.

**MIT LICENSE added early.** The spec schedules it for Phase 19, but "open
source under MIT" is a product principle and an unlicensed public repo is
ambiguous from its first commit.

## Verified against a real server (2.37.1, 2026-10-22)

`scripts/probe-abs.py` checks every assumption Firelight's decoders make
against a live server and prints a report with no token, username, password or
hostname in it. Re-run it when ABS updates — the spec asks for testing against
the current release and the one before it.

Everything passed. Three things it settled that the source alone could not:

- `x-return-tokens: true` really is what returns the refresh token; without the
  header it is `null`, exactly as the code assumes.
- `/auth/refresh` **rotates** the refresh token, which makes `AuthStore`'s
  single-flight refresh a requirement rather than a precaution.
- `/api/libraries/:id/personalized` returns an array of
  `{ id, label, labelStringKey, type, total, entities }` — previously unverified.

It also found one real bug: **ABS sends `""` rather than `null` for absent
metadata**, which `if let` happily passes through to the UI as a blank detail
row and a nameless series facet. Fixed in `LibraryStore.nonEmpty`, with tests
built from the exact payload the server sent.

`scripts/probe-abs-sync.py` then covered the write paths — the ones Phase 4
lives on — and they all passed:

- `POST /api/session/local` returns 200 for the exact shape Firelight sends,
  **and ABS adopts the session's position**. The offline queue drains.
- `mediaProgress` has every field the decoder expects; `lastUpdate` is epoch
  milliseconds; `episodeId` is null for a book.
- All three `POST /api/session/:id/close` shapes return 200. Probe 1's single
  failure was the container going down mid-run, not a defect — re-running
  against a healthy server passes.

That probe had a bug of its own, now fixed: it cleaned up by calling
`DELETE /api/me/progress/<libraryItemId>`, but that endpoint takes the media
**progress** id. The wrong id 404s silently, so the first run left a position
behind on the live server.

Still unverified, because nothing exercises them yet: multi-file books (every
book probed was single-track, so `TrackTimeline` has still never converted a
real offset), podcasts, ebook reading end to end, and OIDC (`authMethods` is
`["local"]`).

## CarPlay is deferred past v1

Cole's decision, 2026-10-22. The CarPlay code is finished and stays in the
repo; only the entitlement is gone.

**Why it had to be removed rather than just left unused:** a build signed with
an entitlement its App ID does not carry fails provisioning. Keeping
`com.apple.developer.carplay-audio` in the file would have blocked every
device build and every submission until Apple granted it.

What is still in place: `App/CarPlaySceneDelegate.swift`, and the
`UIApplicationSceneManifest` entry declaring the CarPlay scene. Both are inert
without the entitlement — iOS simply never creates the scene, which was
verified on a simulator.

### Turning it back on

1. Request the entitlement at `developer.apple.com/contact/carplay/`, category
   **Audio**. This can be done at any time and does not affect App Store
   review of v1.
2. When Apple grants it, add it to the App ID in the developer portal and
   regenerate the provisioning profile.
3. Put this back in `App/Firelight.entitlements`:
   ```xml
   <key>com.apple.developer.carplay-audio</key>
   <true/>
   ```
4. `scripts/build.sh generate` and build. Nothing else changes.

Note that the **first build shipping CarPlay carries extra review risk** —
reviewers exercise the CarPlay interface, and driver-distraction violations of
the CarPlay HIG are a known rejection cause. Exercise it in TestFlight first;
the Xcode CarPlay Simulator is gated on the same entitlement, so there is no
way to test it before the grant.

## CBR: approved, with a substitution

Cole approved RAR support on 2026-10-22 on the licence terms below.

**The spec names UnrarKit, and Firelight does not use it** — UnrarKit has no
`Package.swift` and cannot be added by SPM at all. Adding it would have meant
introducing CocoaPods or vendoring its source into the repo.

`mtgto/Unrar.swift` wraps the **same rarlab UnRAR source**, so the licence
position Cole approved is unchanged, and its own wrapper is **MIT** rather
than UnrarKit's BSD-2-Clause — marginally better for an MIT project.

The UnRAR licence, which Firelight now inherits and must reproduce in its
documentation before release:

- Free use and redistribution, including commercially.
- The source **may not** be used to build a RAR *compressor*. Firelight only
  ever decompresses.
- All copyrights to RAR and UnRAR remain with Alexander Roshal, and the
  notice must appear in the documentation.

**Phase 19's release prep must put that notice in the README and the
acknowledgements**, or redistribution is out of compliance.

## Blocked — needs Cole

- [ ] **watchOS simulator platform.** Only watchOS 27.0 is installed, which
      Xcode 26.4 cannot use; watchOS 26.4 is missing. `FirelightWatch` has
      never been compiled. Install via Xcode > Settings > Components.
- [ ] **Development team.** Signing is on Automatic with no team set, so
      simulator builds work and device installs do not. Open the project in
      Xcode once and pick your team.
- [ ] **Developer portal.** The App ID needs App Groups
      (`group.com.colewilliams.firelight`) and Keychain Sharing
      (`com.colewilliams.firelight.shared`) before the app will install on a
      device. The Settings > Foundation section will show all three checks
      failing until it does.
- [ ] A test ABS server with books, a podcast, and an EPUB, PDF, CBZ, CBR,
      MOBI and AZW3 — needed from Phase 1 onward and for every checkpoint.
- [ ] Four tip products in App Store Connect (Phase 8).
- [ ] Hardcover API token (Phase 17).

## Known issues

- `FirelightWatch` is unverified: written, never compiled. Treat its code as
  untested until the simulator platform is installed.
- `ProgressPosition.progressID` builds a podcast progress id as
  `"\(itemID)-\(episodeID)"` from the spec's description. Confirm against ABS's
  `MediaProgress` model in Phase 11.
- `ServerStatus` does not decode `authFormData`; its shape depends on which
  auth providers are configured. Decode it when OIDC lands in Phase 1.
- **No widget has been seen on a home screen.** Live Activities, the Dynamic
  Island, the lock-screen accessories and Siri phrases all compile and are
  unit-tested where there is logic to test, but none has been rendered by the
  system. Widget layout problems only appear on a device.
- The streak counts only *local* journal entries, so it starts at zero on a
  fresh install even if the server has months of history.
- **CarPlay has never run, and is not in v1.** The code is finished and
  dormant; see "CarPlay is deferred past v1" above.
- **No podcast has been loaded.** Your test library has no podcast, so every
  podcast path is untested against real data.
- **CBR has never been opened.** The RAR path compiles and uses the same
  reader as CBZ, but no `.cbr` has been unpacked — RAR cannot be created
  without a compressor, so there is no fixture for it. A real CBZ *is* tested
  end to end, from archive to decoded images to exported PDF.
- **No tip has been purchased and nothing has been emailed.** The StoreKit
  flow needs the four products in App Store Connect; Send to Kindle needs a
  real Kindle address and a device with mail set up.
- The accessibility pass was done as each phase was built — VoiceOver labels,
  Dynamic Type throughout, Reduce Motion honoured, no fixed font sizes — but
  it has **not** been audited with VoiceOver running or at the largest
  accessibility text size on a device.
- **No book has ever been opened.** Readium integration compiles but has never
  parsed a real EPUB, and the PDF reader has never had a file. The local HTTP
  server Readium needs is unexercised.
- Readium pulls in a sizeable transitive set: Zip, GCDWebServer, SwiftSoup,
  SQLite.swift, ZIPFoundation, CryptoSwift, Fuzi and DifferenceKit. All are
  MIT, BSD-3, Apache 2.0 or zlib, so all fall inside the spec's licence policy.
- **Nothing has ever been downloaded.** Background transfers, resuming after
  the app is killed, and the move out of the temporary directory are all
  untested without a server. Pause stores resume data but does not yet use it
  to resume — it currently restarts the file.
- **The socket's progress event name is not verified from source.**
  `SocketAuthority.js` takes event names as parameters, so the emitting call
  sites are elsewhere. The client listens for both
  `user_item_progress_updated` and `user_media_progress_updated` and ignores
  anything else; confirm against a live server and drop the spare.
- Socket.IO pulls in **Starscream** transitively (Apache 2.0, which the spec's
  licence policy allows).
- **No audio has ever come out of this.** The engine, the session handling,
  the multi-track offsets and the Now Playing wiring are all unexercised
  without a server. Audio interruptions (a call mid-chapter), route changes
  (AirPods out) and background playback are untested.
- Progress reports straight into the ABS session. Phase 4 replaces that with
  the journal, which is what makes it survive being offline — until then, a
  position listened to without a connection is lost.
- The cover-to-player transition uses `matchedGeometryEffect` between the mini
  player and the full player. The spec's richer "cover lifts out of the shelf"
  animation is not in yet.
- Spotlight indexes the cached library rather than downloaded items, since
  downloads arrive in Phase 5. It is capped at the 500 most recently added.
- Series ordering is parsed from ABS's `"Discworld #5"` display string, because
  the minified payload carries no structured series link. A series whose name
  itself ends in `#` plus a number would be misparsed.
- **Nothing in Phases 1 or 2 has touched a real server.** The mock covers the
  protocol, not the deployment: a real reverse proxy, a real self-signed
  certificate and a real OIDC provider are all untested. The SSO flow in
  particular has never run end to end.
- Signing out hits `/logout` before clearing local tokens; if the server is
  unreachable the refresh token stays valid server-side until it expires.
- The app icon is a generated placeholder mark (`scripts/make_app_icon.py`),
  good enough to ship a beta, not a designed identity.
