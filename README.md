# Firelight

A free, open-source, native iOS client for self-hosted
[Audiobookshelf](https://www.audiobookshelf.org) servers. It plays audiobooks
and podcasts, and reads ebooks like a Kindle.

> **Status: pre-release.** Every phase of the build plan is implemented, but
> nothing has been through a public beta. See `PROGRESS.md` for exactly what
> has and has not been verified against a real server and a real device.

## What it does

- **Audiobooks.** Chapter-aware scrubbing, 0.5×–3.5× speed remembered per
  book, smart rewind, a sleep timer that fades out and extends when you shake
  the phone, and bookmarks that sync.
- **Never loses your place.** Every position is written to a local journal
  *before* any network call, so a tunnel, a crash or a flat battery cannot cost
  you your spot. When two devices disagree by more than a couple of minutes,
  Firelight asks instead of guessing.
- **Offline.** The library renders from a local cache, downloads survive the
  app being killed, and a downloaded book plays with no connection at all.
- **Ebooks.** EPUB and PDF, with typography, themes, highlights, notes and
  Markdown export. Comics (CBZ and CBR). Kindle formats are converted to EPUB
  on first open.
- **Podcasts.** Show pages, per-episode progress, and an Up Next queue that
  mixes books and episodes.
- **The rest of the system.** Live Activities, Dynamic Island, home and lock
  screen widgets, Siri and Shortcuts, and Handoff. CarPlay is written but not
  enabled in v1, pending Apple's entitlement.

## What it does not do

- **Collect anything.** No analytics, no ads, no crash-reporting SDK, no
  accounts of ours. The App Store privacy label is "Data Not Collected", and
  `App/PrivacyInfo.xcprivacy` is the machine-readable version of that promise.
- **Charge for anything.** There is a tip jar. It unlocks nothing, and the
  thank-you screen says so.
- **Need a server of ours.** Everything works against a stock Audiobookshelf
  install. Anything Audiobookshelf cannot store — highlights, reader settings —
  goes in your own private iCloud, never ours.

## Building

Requires Xcode 26.4 or newer and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
scripts/build.sh          # generate the project, build, run the tests
```

**Do not edit `Firelight.xcodeproj`** — it is generated from `project.yml` and
is not tracked. See `CLAUDE.md` for conventions and `ARCHITECTURE.md` for how
the modules fit together.

Before installing on a device you will need to set your development team in
Xcode, and add App Groups, Keychain Sharing and iCloud to the App ID in the
developer portal.

## Licence

Firelight is MIT. See [LICENSE](LICENSE).

### Third-party

| Component | Licence |
| --- | --- |
| [Readium Swift Toolkit](https://github.com/readium/swift-toolkit) | BSD-3-Clause |
| [Nuke](https://github.com/kean/Nuke) | MIT |
| [Socket.IO-Client-Swift](https://github.com/socketio/socket.io-client-swift) | MIT |
| [Starscream](https://github.com/daltoniam/Starscream) | Apache-2.0 |
| [Unrar.swift](https://github.com/mtgto/Unrar.swift) | MIT |
| [foliate-js](https://github.com/johnfactotum/foliate-js) | MIT |
| [JSZip](https://github.com/Stuk/jszip) | MIT |
| SwiftSoup, SQLite.swift, ZIPFoundation, Fuzi, Zip | MIT |
| CryptoSwift | zlib-style |
| DifferenceKit, GCDWebServer | Apache-2.0 / BSD-3-Clause |

### UnRAR notice

Firelight reads `.cbr` comics using the UnRAR source, bundled through
Unrar.swift. As its licence requires:

> All copyrights to RAR and the utility UnRAR are exclusively owned by the
> author — Alexander Roshal. The UnRAR source may be used in any software to
> handle RAR archives without limitations free of charge, but cannot be used to
> develop RAR (WinRAR) compatible archiver and to re-create RAR compression
> algorithm, which is proprietary.

Firelight only ever decompresses.
