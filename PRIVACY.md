# Privacy Policy

**Firelight** · Last updated 22 October 2026

## The short version

Firelight collects nothing. There is no analytics, no advertising, no crash
reporting, no tracking, and no account with us — because there is no "us" to
have an account with. Firelight is a client for a server **you** run. It talks
to that server and to nothing else unless you explicitly turn on one of the
optional features listed below.

The App Store privacy label for Firelight is **Data Not Collected**, and that
is the whole truth rather than a technicality.

## What stays on your device

All of it, by default:

- **Your server's address and your credentials.** Stored in the iOS Keychain,
  in a shared access group so the app, its widgets and the share extension can
  reach the same tokens. Never written to logs or diagnostics — the app
  redacts server addresses and tokens before anything is written down.
- **A cache of your library.** Titles, authors, cover art, chapters and
  progress, kept so the app works without a connection.
- **Your listening and reading positions**, written to a local journal before
  they are sent anywhere, so a lost connection cannot lose your place.
- **Downloaded books**, in the app's own container.

None of this is transmitted to anyone. Deleting the app deletes all of it.

## What Firelight sends, and where

**To your Audiobookshelf server, and only the one you configured:** your
sign-in, requests for your library and files, and your playback positions.
That is the whole point of the app. Your server is yours; what it logs is
between you and it.

Firelight has no server of its own. There is no telemetry endpoint, no
"phone home" on launch, and no third-party SDK embedded in the app.

## Optional features that involve someone else

Each of these is off until you turn it on, and each is the only thing that
sends data anywhere other than your own server.

- **iCloud sync for highlights.** If you are signed into iCloud, the passages
  you highlight and the notes you write sync through *your* private iCloud
  database so they follow you between your devices. This is Apple's
  infrastructure and your private storage; the developer cannot read it. Your
  library, positions and downloads are **not** synced — they stay on each
  device.
- **Hardcover.** If you paste a Hardcover API token into Settings, Firelight
  sends the title, author and reading status of books you finish to
  Hardcover so your shelves there stay current. Nothing is sent until you
  supply a token, and removing the token stops it. Hardcover's own privacy
  policy governs what they then do with it.
- **Send to Kindle.** If you send an ebook to your Kindle, the file goes
  through your own mail or share sheet to the Kindle address you entered.
  Amazon's terms govern what happens after that.
- **Tips.** Tips are processed by Apple through In-App Purchase. Apple does
  not share your payment details with the developer, and the developer never
  sees them. Tips unlock nothing; the whole app is free.
- **Catch Me Up.** Summaries are produced by Apple's on-device model on
  supported devices. The text never leaves your phone, and the model is never
  given anything past where you have read.

## Children

Firelight has a Kids Mode that simplifies the library and can be locked behind
your device passcode. It changes what is shown; it collects nothing, because
nothing is collected from anyone.

## Changes

If this policy ever changes, the new version will be published here and the
date above will change with it. Firelight is open source — if you would
rather verify than trust, the code is the policy:
every network call the app can make is in `ABSEndpoints.swift` and
`HardcoverClient.swift`.

## Contact

Open an issue on the Firelight repository.
