# Invite links

## Bottom line

- The link is `https://scwill12.github.io/firelight/join#<payload>`. Ordinary
  https, so it is clickable anywhere and renders as a titled card rather than
  a wall of characters.
- **The payload is in the fragment on purpose.** Everything after `#` never
  reaches a server. iMessage, Slack and WhatsApp all fetch links to build
  previews — a query string would hand the credential to every one of them
  before the recipient tapped it.
- Three things are not built yet and each needs a decision: a repo to serve
  the association file, the associated-domains capability, and the fact that
  an App Store fallback cannot work until the app is on the App Store.

## What the link does

| Situation | What happens |
| --- | --- |
| Firelight installed, association live | The app opens on the invitation screen |
| Firelight not installed | Safari opens the page, which offers the App Store |
| Association not yet set up | Safari opens the page; the app is not offered |

## 1. The association file — DONE

Live and serving:

```
https://scwill12.github.io/.well-known/apple-app-site-association   200
https://scwill12.github.io/join/                                    200
```

Served from the `scwill12.github.io` repository, because Apple validates
Universal Links only from the **domain root** and on GitHub Pages the root
belongs to a user-site repository, not a project one. `.nojekyll` is in that
repo for a reason: Jekyll skips any directory beginning with a dot, so
without it `.well-known` is never published.

The link path is `/join`, not `/firelight/join`, so it cannot collide with
the project repository's own Pages site if that is ever turned on — and the
link is shorter.

**The one known risk.** The file comes back as
`content-type: application/octet-stream`; GitHub Pages cannot be told to
serve it as `application/json`. Apple's CDN has tolerated this for years, but
if the association refuses to validate, this is the first thing to check, and
the fix is a custom domain behind something that can set headers.

The Team ID is in that file in public, which is unavoidable: Apple's design
requires it, and every app using Universal Links publishes its own. That is
why it is there and still not in `project.yml`.

## 2. The capability — NEEDS YOU

This is the only thing standing between the link and the app opening.

1. developer.apple.com → Identifiers → `com.colewilliams.firelight` → tick
   **Associated Domains** → Save.
2. Then add this back to `App/Firelight.entitlements`:

```xml
<key>com.apple.developer.associated-domains</key>
<array>
    <string>applinks:scwill12.github.io</string>
</array>
```

It was added, **tried, and reverted**, because automatic signing will not add
this capability on its own and a device build fails outright without it:

```
Provisioning profile "iOS Team Provisioning Profile: com.colewilliams.firelight"
doesn't include the Associated Domains capability.
```

That is the CarPlay lesson again: an entitlement the App ID does not carry
fails provisioning, so it stays out of the file until the capability exists.

## 3. The App Store fallback has an ordering problem

The page cannot send anyone to the App Store until Firelight is on the App
Store. Until then it should offer TestFlight, or say plainly that the app is
not released yet. A button that leads to a 404 is worse than no button.

## What the page needs to serve

`/firelight/join`, with:

- OpenGraph tags, so the message shows a card. `og:title` is what the
  recipient reads before tapping — "Join a library on Firelight" rather than
  a URL.
- A short explanation and an App Store (or TestFlight) button.
- **No JavaScript that reads the fragment and sends it anywhere.** The whole
  point of the fragment is that the credential stays on the device. The page
  must never transmit it, log it, or put it in an image URL.

## The security model, in one paragraph

The link carries a temporary password that the admin never sees and never
tells anyone. The invitation screen trades it immediately for one the invited
person chooses, and Audiobookshelf invalidates every other session for that
account when the password changes — so a redeemed link is a spent match. The
limit is the window before redemption: until then the link *is* the account,
and anyone who reads it first gets in. That is why the invited account is
created with no update, delete or upload permission, and why the link carries
an expiry.
