# App Store metadata

Draft copy for App Store Connect. Character limits are Apple's and are
counted here; anything with `<fill in>` needs a decision from you.

## Name and subtitle

**Name** (30): `Firelight`

**Subtitle** (30): `Your Audiobookshelf library` — 27

## Promotional text (170)

Editable without a new build, so use it for what changes.

> A free, open-source player and reader for your own Audiobookshelf server.
> No accounts, no ads, no tracking — just your library, on your phone, online
> or off.

164 characters.

## Description

> Firelight is a native iOS client for Audiobookshelf, the self-hosted
> audiobook and ebook server. If you run Audiobookshelf, Firelight is the app
> for listening and reading on your phone.
>
> LISTENING
> Chapter-aware playback with a scrubber that understands where chapters
> start. Adjustable speed per book, a sleep timer you can extend by shaking
> the phone, and smart rewind that backs up a little when you return after a
> pause — more when you have been away longer. Bookmarks sync to your server.
>
> READING
> EPUB, PDF and comics, with your highlights and notes kept across your
> devices through your own iCloud. Kindle files are converted on the phone.
> Follow along in print: tell Firelight how long your own copy is and it
> shows roughly where you would be on the page while you listen.
>
> OFFLINE
> Downloads are first-class. Your library, your covers, your place in every
> book — all cached, so the app opens and works with no connection at all.
> Positions are written down before they are sent, and reconciled when you
> are back.
>
> NEVER LOSES YOUR PLACE
> Positions sync both ways with your server. When Firelight finds a position
> from another device that is far from where you are, it asks before moving
> you instead of silently jumping.
>
> THE REST OF THE SYSTEM
> Live Activities and the Dynamic Island, home and lock screen widgets, Siri
> and Shortcuts, Handoff between devices, and a Kids Mode that can be locked
> behind your passcode.
>
> PRIVACY
> Firelight has no servers of its own, no analytics, no advertising and no
> crash reporting. It talks to the Audiobookshelf server you configure and to
> nothing else. It is free, with no paid tier — the tip jar unlocks nothing.
>
> Firelight is open source under the MIT licence. It requires an
> Audiobookshelf server; it is not affiliated with the Audiobookshelf
> project.

## Keywords (100, comma-separated)

```
audiobookshelf,audiobook,ebook,epub,self-hosted,player,listen,reader,podcast,offline,comics
```

92 characters. No spaces after commas — they count. Do not repeat the app
name or the subtitle; Apple already indexes those.

## What's New

For 1.0:

> First release.

## Category and age

- Primary: **Books**
- Secondary: **Entertainment**
- Age rating: complete the questionnaire honestly. Firelight itself contains
  no content; it plays what is on your server. Expect **4+** unless you
  declare otherwise.

## URLs

| Field | Value |
| --- | --- |
| Privacy policy | `https://scwill12.github.io/firelight-privacy/` |
| Support | needs a public home — Firelight's repo is private |
| Marketing | optional, the repo README is fine |

The privacy policy is live and verified. **Support URL is still open**: App
Store Connect requires one, and the usual answer — the repository's issues
page — is not reachable while Firelight's repo is private. Either make that
repo public, or point support at a page in `firelight-privacy`.

## App Review notes

Paste this, with the demo step matching whatever shipped:

> Firelight is a client for Audiobookshelf (https://audiobookshelf.org), a
> self-hosted audiobook and ebook server. It has no accounts of its own and
> no server of ours.
>
> No sign-in is needed to review the app. On the first screen, tap
> "<the demo button's label>" to load a small built-in sample library with an
> audiobook, an ebook and a comic. Everything in the app can be exercised
> from there: playback, chapters, the reader, downloads and settings.
>
> To see the real flow, Settings > Servers > Add a server takes an
> Audiobookshelf address and credentials. That path needs a server, which is
> why the sample library is built in.

If the demo mode is not in the build being submitted, replace the middle
paragraph with live demo server credentials instead — a reviewer who cannot
get past the first screen will reject the app as non-functional.

## Export compliance

Already answered in `App/Info.plist`:
`ITSAppUsesNonExemptEncryption` is `false`. Firelight uses HTTPS and the
system Keychain only, both exempt. The annual prompt will not appear.
