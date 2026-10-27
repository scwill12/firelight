# Firelight — working notes for Claude Code

A free, open-source, native iOS client for self-hosted Audiobookshelf servers.
`SPEC.md` is the contract; this file is what a fresh session needs to be useful
in five minutes. `PROGRESS.md` says where we are, `ARCHITECTURE.md` says how it
fits together.

## Build and test

```bash
scripts/build.sh            # generate, build, test
scripts/build.sh generate   # regenerate the .xcodeproj after editing project.yml
scripts/build.sh test       # unit tests on a throwaway iPhone 16 Pro simulator
```

**Never edit `Firelight.xcodeproj`.** It is generated from `project.yml` by
XcodeGen (`brew install xcodegen`) and is not in git. Adding a file to a target
folder is enough — regenerate and it is picked up. Changing targets, build
settings or dependencies means editing `project.yml`.

## Conventions

- Swift 6 language mode, strict concurrency, `iOS 18` floor. iOS 26 APIs are
  used behind `if #available(iOS 26.0, *)` with a deliberate iOS 18 fallback —
  see `DesignSystem/GlassSurface.swift` for the pattern.
- **Inject everything.** No singletons. `AppEnvironment` is built by
  `.live()`, `.preview()` or a test's own construction.
- **No hard-coded user-facing strings.** Every one lives in a String Catalog.
  Package modules use `Text("…", bundle: .module)`; app and extension targets
  use their own `Localizable.xcstrings` and a bare `Text("…")`.
- **No hard-coded numbers in UI.** Spacing, radius, motion and colour come from
  `DesignSystem` tokens.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest.

## Gotchas found the hard way

- `Bundle.module` is *internal* to a package. It cannot appear in a public
  initialiser's default argument. Take `Text? = nil` and resolve in the body.
- `UIDevice.current` is main-actor isolated under Swift 6.
  `DeviceIdentity.current()` is `@MainActor` and caches the label;
  `DeviceIdentity.cached()` is the non-isolated reader for background work.
- An app extension that links a SwiftUI package must declare *every* package
  product it transitively uses, or it fails at link time with a confusing
  `SwiftUICore ... not an allowed client` error. The real message is the
  `missing a dependency on X` warning above it.
- `$(AppIdentifierPrefix)` is build-time only. Each target's Info.plist carries
  an `AppIdentifierPrefix` key so `KeychainStore` can assemble the shared access
  group at runtime. Without it the shared Keychain silently falls back to
  per-target storage.
- `URLSession` moves `httpBody` into `httpBodyStream` before a `URLProtocol`
  sees it. `MockABSURLProtocol` reads both; a mock that only reads `httpBody`
  sees every POST as empty.
- String Catalog keys that differ only by **case** ("Sign In"/"Sign in") or
  **trailing punctuation** ("Thank you"/"Thank you.") generate the same symbol
  and fail the build. So does any key too close to a Swift keyword ("Type").
- `ByteCountFormatter` is a mutable class and not `Sendable`, so it cannot be
  a shared `static let` under Swift 6. Build it per call.
- `??` takes an autoclosure, which cannot contain `await`. Bind the awaited
  value first.
- Changing actor isolation inside a local package can leave a **stale module
  cache**: the test target keeps reporting the old isolation error until
  `xcodebuild clean`. If an isolation fix "doesn't take", clean before
  debugging it further.
- `#require` nested inside another `#require` is a recursive macro expansion
  and fails to compile. Bind the inner value first.
- A `@MainActor` class's `deinit` is nonisolated and cannot touch non-Sendable
  stored properties. Tear observers down explicitly instead.
- A `static` member of a `@MainActor` type is main-actor isolated too, which
  makes it unusable from a synchronous test. Mark pure helpers `nonisolated`.
- `AVPlayer` resets its `rate` to 1 whenever it resumes from a stall or moves
  to a new item, so the speed has to be re-applied on `timeControlStatus`
  changes. Setting `rate` on a *paused* player starts playback.
- `tabViewBottomAccessory` is iOS 26 only; `safeAreaInset` is the iOS 18
  fallback.
- A `#Predicate` that ORs several `localizedStandardContains` calls fails with
  "unable to type-check this expression in reasonable time". Denormalise into
  one field instead.
- `@Entry` environment defaults are nonisolated, so a `@MainActor` type cannot
  be their default value. Make the entry optional.
- **A SwiftData migration stage must change every store the plan covers.**
  The container has two configurations (local cache, synced highlights) under
  one `SchemaMigrationPlan`. A new schema version that touches only one of
  them leaves the other's checksum identical between stages, and SwiftData
  throws `Duplicate version checksums across stages` at container open — the
  app cannot start. Adding a model to either side therefore means a no-op
  bump on the other, or a second `ModelContainer` with its own schema.
  `ReadingEditionStore` sidesteps it entirely by living in defaults; see its
  comment before reaching for `@Model` again for something small.
- The `Package` initialiser requires `dependencies:` to come *after*
  `products:`.
- Simulator taps are in **device points** (402×874 on an iPhone 16 Pro), not
  screenshot pixels. Divide screenshot coordinates by the scale factor first.
- `Section(isExpanded:)` has no variant that also takes a `footer`. Use a
  plain section, or move the explanation into the content.
- Two catalog keys that differ only by case ("Sign In" / "Sign in") collide in
  generated string symbols and fail the build. Keep keys distinct.
- Swift 6 will not let a `@Sendable` closure mutate a captured `var`. Test
  spies that record calls need an actor, not a local variable.
- **`xcodebuild -only-testing:` against a Swift Testing `@Test` can match
  nothing, run nothing, and still exit 0.** The log reads `Test Suite
  'Selected tests' passed` with the start and end timestamps in the same
  millisecond, and further down, `Executed 0 tests`. Since every test here is
  Swift Testing rather than XCTest, a filtered run that "passes" proves
  nothing on its own. Grep the log for `Executed 0 tests` before believing a
  green filtered run.
- **A closure handed to an Apple framework must be created somewhere
  non-isolated.** A closure written inside a `@MainActor` method *inherits*
  that isolation, Swift emits a runtime executor check, and the check traps
  when the framework calls back on its own queue. This killed the app on every
  single play: `MPMediaItemArtwork`'s request handler is called on
  MediaPlayer's `accessQueue`. `AppEnvironment.artwork(for:)` is `nonisolated`
  for exactly this reason — read its comment before touching it. Same trap,
  different framework, as the two KVO handlers below.
- **`MainActor.assumeIsolated` in a KVO handler is a crash.** KVO is delivered
  on whichever thread changed the value, and `AVPlayer` changes `rate` and
  `timeControlStatus` from its own queues, so assuming main-actor isolation
  there trapped the instant playback started. `addPeriodicTimeObserver` and
  `NotificationCenter` take a `queue:` and are safe when given `.main`;
  `observe(_:options:changeHandler:)` takes no queue, so read the values in
  the handler and hop with `Task { @MainActor in }`. Never let the `AVPlayer`
  itself cross — it is not `Sendable`.
- `AVPlayer.seek` with a non-numeric `CMTime` raises an Objective-C exception
  Swift cannot catch. Every seconds-to-`CMTime` conversion goes through
  `AudioEngine.playableTime`, and `max(.nan, 0)` is `.nan`, so clamping
  against a possibly-indefinite duration uses `AudioEngine.clamp`.
- `DEVELOPMENT_TEAM` is set in the generated `.xcodeproj`, not in
  `project.yml` — so **regenerating wipes it** and device builds stop signing.
  Re-set it in Xcode afterwards, or add it to `project.yml`.
- A `.aspectRatio(contentMode: .fill)` image reports the size *it* wants, not
  the one it was proposed, so `.frame(width:height:)` around it only positions
  an oversized view — it spills over its neighbours and past the screen margin.
  Lay it out inside a `Color.clear.overlay { … }` and clip that. This is what
  `CoverImage` does; copy it for any other filled artwork.
- Covers come in every aspect ratio. `CoverArt.aspectRatio` is the one slot
  they all go in, cropped to fill. Do not pick a ratio at a call site.
- `Typography.timecode` is for a clock that is *running*. A length read once
  (`"22h 30m left"`) uses `Typography.duration`; monospacing it made the
  library look like a terminal.
- A fixed-size thumbnail beside Dynamic Type text breaks apart at the larger
  sizes. Use `@ScaledMetric` for artwork that sits next to scaling text.
- The watchOS **26.4** simulator platform is not installed on this machine
  (only watchOS 27.0, which Xcode 26.4 cannot use). `FirelightWatch` therefore
  cannot be compiled here until it is installed via Xcode > Settings >
  Components.

## Audiobookshelf API — verified, not guessed

Checked against `advplyr/audiobookshelf` `master`: `server/Server.js`,
`server/Auth.js`, `server/routers/ApiRouter.js`.

Root router (**not** under `/api`, no auth): `GET /status`, `GET /ping`,
`GET /healthcheck`, `POST /login`, `POST /logout`, `POST /auth/refresh`.
Everything else lives under `/api` behind the auth middleware.

- `GET /status` → `app`, `serverVersion`, `isInit`, `language`, `authMethods`,
  `authFormData`. `GET /ping` → `{"success": true}`.
- **`POST /login` must send `x-return-tokens: true`.** Without it ABS returns
  `user.refreshToken: null` and sets an http-only cookie instead, which is no
  use to a native client. With it, both tokens are in the body.
- Login/refresh payload: `user`, `userDefaultLibraryId`, `serverSettings`,
  `ereaderDevices`, `Source` — note the capital S on `Source`. The user object
  is `toOldJSONForBrowser()`, the same shape `GET /api/me` returns.
- `POST /auth/refresh` reads the refresh token from the `x-refresh-token`
  header (which overrides the cookie, and is what makes the new refresh token
  come back in the body).
- Auth is `Authorization: Bearer <accessToken>`; ABS also accepts `?token=`.
- Refresh tokens arrived in **2.26.0**. Legacy `user.token` still works on
  servers that have not removed it.
- The server can be hosted under a sub-path (`RouterBasePath`), so never build
  a URL by discarding the base URL's path.

Progress and sync (for Phases 4 and 11):
`PATCH /api/me/progress/:libraryItemId/:episodeId?` — note the episode id is
part of the *path*, and `PATCH /api/me/progress/batch/update` exists for
draining a queue. Offline sessions go to `POST /api/session/local` (and
`/session/local-all`). Bookmarks: `POST|PATCH /api/me/item/:id/bookmark`,
`DELETE /api/me/item/:id/bookmark/:time`.

**`DELETE /api/me/progress/:id` takes the media *progress* id, not the library
item id.** The two are different UUIDs and the wrong one 404s silently — the
first run of `probe-abs-sync.py` did exactly that and left a position behind on
a real server. `mediaProgress[].id` is the one to pass. Firelight does not
delete progress anywhere yet; if a phase ever needs to, this is the trap.

**Verified live (2.37.1):** `POST /api/session/local` returns **200** for the
exact `LocalPlaybackSession` shape Firelight sends, and ABS adopts the
session's `currentTime` as the user's position — so the offline queue really
does drain. `mediaProgress` carries all fifteen fields the decoder expects
(plus `userId`), `lastUpdate` is epoch milliseconds, and `episodeId` is null
for a book. All three `POST /api/session/:id/close` shapes return 200, with or
without a body.

Playback sessions (verified in `objects/PlaybackSession.js` and
`objects/files/AudioTrack.js`, for Phase 3):
- `POST /api/items/:id/play` (and `/play/:episodeId`) opens a session. The
  client payload adds `audioTracks`, `libraryItem` and `coverAspectRatio` to
  the stored session, alongside `id`, `libraryItemId`, `episodeId`, `chapters`,
  `displayTitle`, `displayAuthor`, `coverPath`, `duration`, `playMethod`,
  `currentTime`, `startTime`, `timeListening`, `startedAt`, `updatedAt`.
- Each audio track has `index`, `startOffset`, `duration`, `title`,
  `contentUrl`, `mimeType`, `codec`, `metadata`. **`contentUrl` is a relative
  path, `/api/items/{itemId}/file/{ino}`, with no token on it** — the client
  has to supply auth itself.
- A book is often several tracks: `startOffset` is what turns a per-track
  position into a book position. Do not assume one file per book.
- Then `POST /api/session/:id/sync` while playing and
  `POST /api/session/:id/close` at the end.

**Auth for media URLs.** `AVPlayer` cannot set an `Authorization` header
through public API, so audio URLs must carry `?token=<accessToken>` — ABS
accepts it (`ExtractJwt.fromUrlQueryParameter('token')`) and the official apps
do the same. `Redaction.url` already strips query strings, so a token can never
reach a log that way. The hardened alternative, if this ever needs to change,
is an `AVAssetResourceLoaderDelegate` that adds the header itself.

Library search is **per-library** (`GET /api/libraries/:id/search`);
`GET /api/search/books` is metadata-provider search, a different thing.

Library payloads (verified in `controllers/LibraryController.js`, for Phase 2):
- `GET /api/libraries` → `{ "libraries": [...] }` — note the wrapper object.
  Each entry is `library.toOldJSON()`; `?include=stats` adds a `stats` key.
- `GET /api/libraries/:id/items` → `{ results, total, limit, page, sortBy,
  sortDesc, filterBy, mediaType, minified, collapseseries, include, offset }`.
  Query: `limit`, `page` (non-negative integers, else 400), `sort`, `desc=1`,
  `filter`, `collapseseries=1`, `minified=1`, `include`. `total` is **omitted**
  on the collapsed-subseries path, so decode it as optional.
- `GET /api/libraries/:id/personalized` — **shape now verified against a live
  2.37.1 server**: an array of shelves, each
  `{ id, label, labelStringKey, type, total, entities }`, with ids
  `recently-added`, `recent-series`, `discover`, `newest-authors`. Firelight
  still does not use it: the spec's smart shelves are ours, computed from the
  local cache, which is what makes them work offline.

**Confirmed against a live server (2.37.1), not just the source:** the
`x-return-tokens` header really is what returns `user.refreshToken` (null
without it); `/auth/refresh` really does **rotate** the refresh token, so the
coalescing in `AuthStore` is required, not defensive; `addedAt`/`updatedAt` are
epoch milliseconds; `contentUrl` is relative and carries no token; the legacy
`user.token` is still issued on 2.37.1.

**ABS sends `""`, not `null`, for absent metadata** — `subtitle`, `narratorName`,
`seriesName`, `publishedYear`, `description` and `ebookFormat` all arrive empty
rather than missing. An empty string survives `if let`, so it reaches the UI as
a blank row and a nameless facet. `LibraryStore.nonEmpty` normalises at the
boundary; do the same for any new field.

Add an endpoint to `ABSEndpoints.swift` only in the phase that uses it, and
only after checking it against the source.

## Where things live

- Library cache: `Persistence/CachedLibraryModels.swift` + `LibraryStore.swift`.
  Schema versions and the migration plan are in `Persistence/Models.swift` —
  **add a new `VersionedSchema` and a stage, never mutate a released one.**
- Home shelves: `Persistence/SmartShelves.swift`, pure and fully tested.
- Screens: `Features/Library/`, one file per screen.
- Covers: `DesignSystem/CoverImage.swift`. Credentials come from
  `LibraryController.coverConfiguration()` and must be refreshed whenever the
  token or active address changes.

## Playback

`PlaybackController` is the only thing that opens a session or writes a
position; `AudioEngine` is the only thing that touches AVFoundation. Everything
above them works in **book time** — `TrackTimeline` converts to and from
per-file time, and if that conversion is wrong every chapter mark after the
first file is wrong with it.

## Progress sync

`ProgressSyncService` is the only thing that records a position, and
`receiveRemote` is the only path by which a position from elsewhere can move
the user. Writes go to the journal *before* the network, always.

Two ABS traps, both verified: an in-session `/sync` sends `timeListened` (a
delta), a local session sends `timeListening` (a total); and ABS replaces any
local session id beginning with `play_local_`, so Firelight sends a UUID and
keeps it so the same offline session can be topped up rather than duplicated.

## Downloads

`BackgroundDownloadManager` owns the background `URLSession`; its identifier is
fixed and its container is the App Group, so the system can hand work back
after the app has been killed. `didFinishDownloadingTo` must move the file
**synchronously** — the temporary file is gone the moment it returns.

A download is only playable when every file has landed; `localTracks` returns
nothing for a partial download on purpose.

## Reading

`EbookFormatDetector` decides the viewer from the file's bytes, not its name.
EPUB goes to Readium, PDF to PDFKit. `EPUBPublicationOpener.open` builds its
retriever and opener **per call** — neither is `Sendable`, so holding them
across an `await` is a data race under Swift 6 — while the local HTTP server
Readium serves resources from is shared and main-actor isolated.

Readium's `Locator` serialises with `try locator.jsonString()`.

## Widgets, Live Activity and intents

Extensions never open the database. The app writes `SharedState.nowPlaying`
(and `listeningStreak`) to the App Group, and widgets read it — a widget has
milliseconds to draw and runs in its own process.

`NowPlayingSnapshot.projected(to:)` advances a playing position by however long
ago it was written; without it a widget's progress bar freezes between
timeline entries. The Live Activity uses `Text(timerInterval:)` so the system
animates the countdown instead of the app pushing one per second.

`PlaybackIntentBridge` is the project's single exception to "no singletons":
App Intents are constructed by the system with nothing to inject into. The app
registers the player at launch; the reference is weak.

`ActivityKit.Activity` is **not** `Sendable`, so Swift 6 rejects awaiting its
`update`/`end` from an actor. `LiveActivityController.ActivityBox` is an
`@unchecked Sendable` wrapper that documents why, rather than scattering
`@unchecked` at call sites.

An `NSUserActivity` type that is not in the app's `NSUserActivityTypes` is
silently ignored — which looks exactly like Handoff being broken. A test
asserts the Info.plist and the constant agree.

## Podcasts and comics

A podcast library item is **not** an `ABSLibraryItem`: `media` is a different
shape and metadata uses `author`, not `authorName`. Use `ABSPodcastItem`.
Episodes come back only on the **expanded** item (`?expanded=1`); the minified
form carries `numEpisodes` and nothing else.

Comics use `ComicArchive`, built on Readium's archive layer — do **not** add
ZIPFoundation, as the upstream package and Readium's fork share a SwiftPM
identity and cannot both resolve. Page order is natural-sorted
(`options: [.numeric, …]`), without which `page10` precedes `page9`.

CBR is RAR, read through `mtgto/Unrar.swift` (MIT wrapper, bundled rarlab
UnRAR source). **The spec names UnrarKit; it has no SPM support and is not
used.** `ComicArchive` picks its backing from the file's *bytes*, so a `.cbz`
that is really a RAR opens correctly.

**Release obligation:** the UnRAR licence requires its copyright notice in the
documentation. Phase 19 must put it in the README and acknowledgements.

## iCloud

Only **highlights** sync. They live in a second `ModelConfiguration` named
`synced`, backed by the user's private CloudKit database; everything else is a
cache of the server and stays on the device.

Three CloudKit rules, all of which fail at **runtime** when the container
opens, not at compile time — so getting one wrong means the app cannot open
its database at all:

1. **No unique constraints.** `HighlightRecord` has no `@Attribute(.unique)`.
2. **Every attribute optional or defaulted.** All of `HighlightRecord`'s
   stored properties carry a default.
3. **`cloudKitDatabase` defaults to `.automatic`.** The moment the iCloud
   entitlement exists, every configuration that does not say `.none` tries to
   sync — including in-memory test stores and the library cache, which
   CloudKit rejects outright. **Every non-synced configuration must pass
   `cloudKitDatabase: .none` explicitly.**

## Conversion and intelligence

`MOBIConverter` runs foliate-js and JSZip in a hidden `WKWebView`; the vendored
JavaScript is in `ConversionKit/Resources` and is declared with `.process`,
not `.copy` — a copied folder called `Resources` collides with the bundle's own
layout and codesign rejects it.

DRM is detected in Swift (`MOBIInspector`) from twelve bytes of the PalmDOC
header, before the web view exists.

`CatchMeUp` truncates text **in Swift** before the model sees it. The model is
never given anything past the reader's position; that rule is the feature.

## CarPlay

Written, and **dormant in v1 by decision**. The entitlement is out of
`Firelight.entitlements` because a build signed with an entitlement its App ID
lacks fails provisioning. `CarPlaySceneDelegate` and the scene manifest stay;
iOS never creates the scene without the entitlement. PROGRESS.md has the
four-step path to switching it on.

## The player's clock

`TimeScope` decides what elapsed and remaining count against — the book, or
the chapter you are in. It is pure and fully tested, and it falls back to book
time whenever a chapter clock would be meaningless (no chapters, or a chapter
with no length), because a clock frozen at zero is worse than the one the
reader was trying to replace. `PlaybackController.timeScope` just resolves it;
the scrubber spans the scope and seeks within it.

## Following along in print

`FollowAlong` maps audio progress onto the listener's own copy. Four numbers,
all theirs: first and last position (what their reader shows at each end of
the text), and the stretch of *audio* those cover. The second pair is the
calibration — an audiobook that opens with a foreword spends minutes where the
page does not move, and an uncalibrated estimate runs ahead for the rest of
the book. `ReadingEdition.window` validates the pair together, because half a
crossed calibration is worse than none.

Kindle counts **locations** — a fixed slice of the file, identical on every
model — and shows pages only when the publisher supplied them. `KindleModel`
therefore changes the help text and nothing else; do not let it grow into
something that claims to change the arithmetic.

Editions live in `ReadingEditionStore`, which is defaults-backed. Its comment
says why, and that reason is a constraint on the whole schema — read it before
adding a `@Model` for anything small.

## The demo library

`DemoKit` is how Firelight shows itself without a server — on the opening
screen, and to an App Store reviewer who will never have one. It is **not** a
mock in the testing sense: `DemoURLProtocol` claims `demo.firelight.invalid`
in the app's own `URLSession`, so the ordinary client, decoders and screens
run against it unchanged.

Two things it cannot reach, both handled:

- **`AVPlayer` does not load through `URLProtocol`.** A demo book is handed to
  the player as *already downloaded*, through `DemoMode.localTracks`, which is
  the app's ordinary offline path rather than a special case.
- **Covers load through Nuke's own session.** `CoverImageProvider.extraProtocolClasses`
  must be set *before* the provider is constructed — its loader reads the
  value once — or a demo shelf draws placeholders.

The demo server is recognised by its **address**, never an id: it is added
through the real `addServer`, which mints its own.

The payloads in `DemoCatalogue` are hand-written, so `DemoLibraryTests`
decodes every one with the app's real decoder. If a model changes shape that
test fails, instead of the sample library quietly emptying itself in front of
a reviewer.

`scripts/make_demo_library.py` regenerates the bundled content: public-domain
text, a synthesised voice, covers drawn from nothing. Nothing in it belongs to
anyone else, and that is a licensing requirement, not a preference.

The script also writes `demo-library.json`, which `DemoCatalogue` decodes at
runtime. **Durations are measured there, not written by hand** — a duration
copied into Swift drifts the first time anyone re-runs the script, and a wrong
one puts every chapter mark after it in the wrong place. Adding a book means
editing the script and re-running it; no Swift changes.

`docs/App-Store-screenshots.md` covers the other thing this library is for:
the store screenshots photograph it rather than a real server, because
publishers' cover art has no business in App Store marketing material.

## Automated runs must not make noise

The screenshot run drives the app into playback so the player screen has a
book to photograph, and the Simulator plays through the speakers of whoever
is sitting at the Mac. There is **no `simctl` mute and no simulator audio
preference** — the Simulator uses the host's default output device — so the
app has to honour it itself.

Launching with `-FirelightSilent` makes `AudioEngine` set the volume to zero
*before* `play()` starts anything. Pausing afterwards is not equivalent:
killing a run part-way skips every cleanup path, which is how two screenshot
runs ended up playing an audiobook into a room. Anything that drives playback
unattended passes the flag.

## The StoreKit configuration must be in Xcode's current format

`App/Firelight.storekit` drives the tip jar in the simulator and on device
when the app is launched from Xcode. It spent a long time returning **zero
products and throwing nothing**, which is the signature of a configuration
file StoreKit cannot use rather than of a wiring problem.

The cause was the file's own shape. It was hand-written as **version 3.0**
with an empty `settings` block, and a configuration with no `_locale` and no
`_storefront` has nothing to resolve prices against. Comparing it against a
file Xcode wrote itself was what settled it. A working file carries:

- `version` `{major: 4, minor: 0}`
- `settings` with `_applicationInternalID`, `_locale` (`en_US`),
  `_storefront` (`USA`), `_failTransactionsEnabled`, `_lastSynchronizedDate`
  and the nine `_storeKitErrors` entries
- an `appPolicies` block
- numeric `internalID`s, not words like `TIP1`

`_developerTeamID` is **deliberately empty**: this file is in a public repo
and the team id stays out of it. Products load fine without it.

Things that were blamed and were not the cause, so nobody repeats them:

- The path. XcodeGen writes `../../App/Firelight.storekit`, which is exactly
  the shape Xcode itself writes — the `../../` escapes
  `xcshareddata/xcschemes` and the remainder is relative to the project
  directory. Every working project on this machine uses the same form. An
  earlier session "corrected" it to `../../../` and genuinely broke it.
  **Leave XcodeGen's output alone.**
- Project membership. It is a member via a second `project.yml` entry with
  `buildPhase: none`, which keeps it out of the shipped bundle. Worth doing,
  verified absent from a Release `.ipa` — but not the fix.
- App Store Connect. A local configuration does not consult it at all.

Do not try to settle this from the command line. `-only-testing:` does not
match a Swift Testing function, so the run executes nothing and exits 0
claiming success — see the `Executed 0 tests` gotcha above — and running the
whole suite to reach one probe risks `AudioEngineLiveTests` playing audio
into the room. ⌘R and look at the screen.

## Invitations

An invitation is a **pasteable code**, never a link. A link needs a domain to
host its landing page on, and a client for self-hosted servers has no business
routing other people's invitations through its author's website. The code is
about 110 characters and carries four fields; the server's name and the
person's name are fetched after redemption rather than carried, which is both
shorter and more accurate. `docs/Invite-codes.md` has the reasoning.

The security model is **spend on redemption**: the code holds a temporary
password the admin never sees, and the invitation screen replaces it with one
the invited person chooses. Audiobookshelf invalidates every other session for
an account when its password changes, so redeeming evicts anyone else holding
the code. Until redemption the code *is* the account — which is why invited
accounts get no update, delete or upload permission, and why codes expire.

Four things verified against the server's source, each of which fails
silently if forgotten:

- `POST /api/users` defaults **`isActive` to false**. An account created
  without it cannot sign in and says nothing about why.
- `PATCH /api/me/password` must send `x-return-tokens`, or the app logs
  itself out at the moment someone accepts: the change invalidates the very
  session making it, and the replacement tokens only come back in the body.
- That endpoint **rejects guests with 403**, so invitations create `user`.
- A plain `user` already defaults to the right permissions. They are sent
  explicitly anyway, so a change to the server's defaults cannot widen them.

Two traps that are about the network rather than the API:

- The invitation carries the server's **`remoteURL`**, not
  `session.baseURL(for:)`. The latter is whichever address this device
  resolved to, which at home is the LAN one — an invitation carrying
  `192.168.x.x` reaches nobody outside the house. The field is editable
  because only the admin knows which address a given person can reach.
- **Custom headers are not carried**, and the invite screen says so when the
  server has any. They are a shared secret that redemption would not spend,
  so a code carrying them would stay dangerous forever. A server behind
  Cloudflare Access needs the person granted there, not handed a token.

## Rules that are not negotiable

1. One phase at a time. Stop at its checkpoint and print the device test list.
2. Never log or display a token, password or full server URL. Use `Redaction`.
3. Never move a user's position without asking when the jump is large. The
   rule lives in `ProgressConflictResolver` and is covered by tests.
4. Every feature ships real loading, empty, error and offline states.
5. Ask before adding a dependency that is not on the approved list in SPEC.md.
