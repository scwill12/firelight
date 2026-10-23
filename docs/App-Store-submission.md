# Submitting Firelight

Every value here is the real one, taken from `project.yml`, the entitlements
and `TipJar.swift`. Type them exactly; a typo in a bundle ID or an App Group
is a provisioning failure half an hour later with an unhelpful message.

## Bottom line

- Three bundle IDs to register, not one. The watch app is not shipping.
- **Both hard blockers are cleared.** The privacy policy is written
  (`PRIVACY.md`, `docs/privacy.html`), and a reviewer can use the whole app
  with no server at all: "Look around first" on the opening screen loads a
  bundled sample library.
- The four tip products must be created *and attached to the first build*,
  or the tip jar is dead on arrival.
- Go to TestFlight first. Most of the app has never run on a device.

## 1. Register the identifiers — ALREADY DONE

Verified, not assumed: a Release archive's signed entitlements carry
`application-groups`, `icloud-container-identifiers`, `icloud-services` and
`keychain-access-groups`. Xcode's automatic signing registered the App IDs and
the capabilities while building to the device, so there is nothing to do in
the portal.

Re-check it any time with:

```bash
codesign -d --entitlements - <path>/Firelight.app
```

The reference below is kept for the day something needs re-creating.

developer.apple.com → Certificates, Identifiers & Profiles → Identifiers.

### App IDs

| Target | Identifier |
| --- | --- |
| App | `com.colewilliams.firelight` |
| Widgets | `com.colewilliams.firelight.widgets` |
| Share extension | `com.colewilliams.firelight.share` |

Do **not** register `com.colewilliams.firelight.watchkitapp`. The watch app is
not embedded in the archive and cannot be built on this machine.

Capabilities to tick on the **app** ID:

- App Groups
- iCloud → CloudKit
- Keychain Sharing

On the **widgets** and **share** IDs, tick App Groups and Keychain Sharing
only. They never open the database or touch iCloud.

### App Group

Identifiers → App Groups → `group.com.colewilliams.firelight`

Assign it to all three App IDs. Without it the share extension and widgets
silently read an empty container — they do not crash, they just show nothing,
which is harder to diagnose.

### iCloud container

Identifiers → iCloud Containers → `iCloud.com.colewilliams.firelight`

Assign to the app ID only. If this is missing the app still runs: the store
falls back to local-only and highlights stop syncing. That fallback is
deliberate, so do not read "it works" as "this is configured".

### Keychain group

No portal entry. It comes from the entitlement
`$(AppIdentifierPrefix)com.colewilliams.firelight.shared`, and each target's
Info.plist carries `AppIdentifierPrefix` so it can be assembled at runtime.

## 2. Create the app record

appstoreconnect.apple.com → Apps → +

| Field | Value |
| --- | --- |
| Platform | iOS |
| Name | Firelight |
| Primary language | English (U.S.) |
| Bundle ID | `com.colewilliams.firelight` |
| SKU | `firelight-ios` (internal only, never shown) |
| User access | Full |

Category: **Books**. Secondary: **Entertainment** or none.

## 3. Create the four tip products

Monetization → In-App Purchases → + , type **Consumable** for each.

| Product ID | Reference name | Display name |
| --- | --- | --- |
| `com.colewilliams.firelight.tip.coffee` | Tip — Coffee | Coffee |
| `com.colewilliams.firelight.tip.snack` | Tip — Snack | Snack |
| `com.colewilliams.firelight.tip.lunch` | Tip — Lunch | Lunch |
| `com.colewilliams.firelight.tip.dinner` | Tip — Dinner | Dinner |

Each needs a price tier, a description, and a 1024×1024 review screenshot.

Two things that get this rejected:

- **Submit them with the first build.** A build that references IAPs which are
  not "Ready to Submit" fails review.
- **They must unlock nothing.** They don't — `TipJar.swift` says so in its
  first comment — but the description must not imply otherwise, or it reads as
  paid functionality that isn't delivered.

## 4. Privacy policy

Written. `PRIVACY.md` is the canonical copy and `docs/privacy.html` is the
hostable one.

Turn on GitHub Pages with the source set to the `docs/` folder on `main`, and
the policy is live at `https://scwill12.github.io/firelight-privacy/` — live, verified with
no further setup. Paste that into App Information → Privacy Policy URL, and
**open it yourself first** — a link that 404s is a rejection.

It discloses the three things that are easy to forget: highlights sync
through the user's own iCloud, the optional Hardcover integration sends
title, author and status to a third party, and send-to-Kindle hands the file
to Amazon. All three are off until the user turns them on, which is what
keeps the label at Data Not Collected.

## 5. Privacy label

App Privacy → **Data Not Collected**.

That answer has to stay true. It is a product principle in `SPEC.md`, not a
form to fill in: no analytics SDK, no crash reporter, no accounts of ours.
Adding any of those later means changing this label.

Export compliance is already handled —
`ITSAppUsesNonExemptEncryption` is `false` in `App/Info.plist`, so the yearly
prompt will not appear. Firelight uses HTTPS and the system Keychain only.

## 6. Version

Set to `1.0.0`. After changing it, regenerate:

```bash
FIRELIGHT_TEAM_ID=<your team id> scripts/build.sh generate
```

Keep `FIRELIGHT_TEAM_ID` exported or the generated project loses its signing
team and device builds stop working.

## 7. Archive and upload

Confirmed working as of the last check — the archive builds and signs with the
app, the share extension and the widgets, and no CarPlay entitlement.

```bash
xcodebuild archive -project Firelight.xcodeproj -scheme Firelight \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/Firelight.xcarchive
```

Or Xcode: destination **Any iOS Device**, Product → Archive → Distribute App →
App Store Connect. Processing takes 5–30 minutes.

## 8. App Review notes — the one that will reject you

**Firelight is useless without an Audiobookshelf server.** A reviewer opens it
and sees an onboarding screen asking for a server address. They have no
server. They cannot get past that screen, so they cannot see the app, so they
reject it as non-functional or as requiring an account without a demo.

Put this in App Review Information → Notes, with real values:

```
Firelight is a client for self-hosted Audiobookshelf servers
(https://audiobookshelf.org). It has no accounts of its own and
no server of ours — it connects only to a server the user runs.

A demo server has been prepared for review:

  Server address: https://<a server reachable from the internet>
  Username: <reviewer account>
  Password: <password>

Enter the address on the first screen, then sign in. The library
contains audiobooks, a podcast and ebooks so every feature can be
exercised.
```

No demo server is required. The sample library is bundled in the app, so it
cannot be offline when the reviewer happens to open it — which matters,
because you do not control when that is.

Its content is `Alice's Adventures in Wonderland` (public domain, 1865), read
by a synthesised voice, with covers drawn at build time. Nothing in it belongs
to anyone else. `scripts/make_demo_library.py` regenerates all of it.

## 9. Screenshots

`docs/App-Store-screenshots.md` has the shot list. Sizes required:

- iPhone 6.9" (iPhone 16 Pro Max)
- iPhone 6.5" or 6.1", depending on what App Store Connect asks for that year
- iPad 13" — only if iPad stays in `TARGETED_DEVICE_FAMILY`

Take them from a simulator signed into a server with real covers. Empty
shelves and placeholder tiles read as an unfinished app.

## Before submitting

- [x] App IDs registered with the right capabilities (verified in the archive)
- [x] App Group assigned
- [x] iCloud container assigned
- [ ] App record created
- [ ] Four consumables created and Ready to Submit
- [x] Privacy policy written, hosted and verified — URL still to be entered in App Store Connect
- [ ] Privacy label set to Data Not Collected
- [x] Version bumped to 1.0.0
- [ ] Build uploaded and processed
- [x] Demo library bundled — no demo server needed
- [ ] Screenshots for every required size
- [ ] TestFlight build used on a real device for more than a few minutes

## What is genuinely untested

As of writing, the device testing covers playback, the player, chapters and
follow-along. The reader, comics, podcasts, downloads, widgets, the share
extension, Siri, Handoff and stats have run in tests and the simulator only.

Two of the three crashes found on the first day of device testing were
device-only behaviour that the full test suite passed straight through. Expect
more in the parts that have not been opened on a phone yet, and use TestFlight
long enough to find them.
