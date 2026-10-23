# Submitting Firelight

Every value here is the real one, taken from `project.yml`, the entitlements
and `TipJar.swift`. Type them exactly; a typo in a bundle ID or an App Group
is a provisioning failure half an hour later with an unhelpful message.

## Bottom line

- Three bundle IDs to register, not one. The watch app is not shipping.
- **Two hard blockers**: there is no privacy policy, and App Review will not
  be able to use the app at all without a demo server. Both reject on sight.
- The four tip products must be created *and attached to the first build*,
  or the tip jar is dead on arrival.
- Go to TestFlight first. Most of the app has never run on a device.

## 1. Register the identifiers

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

## 4. Privacy policy — missing, and required

There is no privacy policy anywhere in this repo. It is required for every
app including free ones with no data collection, and a missing URL is an
instant rejection.

It can be short, because the truth is short: Firelight collects nothing, has
no analytics and no accounts, talks only to the server the user configures,
and keeps everything on the device or in the user's own iCloud. Host it on
GitHub Pages from this repo and paste the URL into App Information.

## 5. Privacy label

App Privacy → **Data Not Collected**.

That answer has to stay true. It is a product principle in `SPEC.md`, not a
form to fill in: no analytics SDK, no crash reporter, no accounts of ours.
Adding any of those later means changing this label.

Export compliance is already handled —
`ITSAppUsesNonExemptEncryption` is `false` in `App/Info.plist`, so the yearly
prompt will not appear. Firelight uses HTTPS and the system Keychain only.

## 6. Version

`project.yml` says `MARKETING_VERSION: "0.1.0"`. That is fine for TestFlight.
Set it to `1.0.0` before submitting to the App Store, then regenerate:

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

The demo server must be reachable from Apple's network — a LAN address will
not work. Options, roughly in order of effort: a Tailscale Funnel or Cloudflare
Tunnel pointed at the existing server, a small VPS running Audiobookshelf with
a handful of public-domain titles, or the project's own demo instance if one
is stood up. Put only public-domain or self-made content on it.

## 9. Screenshots

`docs/App-Store-screenshots.md` has the shot list. Sizes required:

- iPhone 6.9" (iPhone 16 Pro Max)
- iPhone 6.5" or 6.1", depending on what App Store Connect asks for that year
- iPad 13" — only if iPad stays in `TARGETED_DEVICE_FAMILY`

Take them from a simulator signed into a server with real covers. Empty
shelves and placeholder tiles read as an unfinished app.

## Before submitting

- [ ] Three App IDs registered with the right capabilities
- [ ] App Group assigned to all three
- [ ] iCloud container assigned to the app
- [ ] App record created
- [ ] Four consumables created and Ready to Submit
- [ ] Privacy policy written, hosted, URL entered
- [ ] Privacy label set to Data Not Collected
- [ ] Version bumped to 1.0.0
- [ ] Build uploaded and processed
- [ ] Demo server live, reachable from outside the LAN, credentials in notes
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
