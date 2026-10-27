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

## 1. The association file, and where it has to live

Universal Links require Apple to fetch:

```
https://scwill12.github.io/.well-known/apple-app-site-association
```

That path is at the **domain root**, and on GitHub Pages the root of
`scwill12.github.io` is served by a repository named exactly
`scwill12.github.io` — not by the `firelight` project repo, which only owns
`/firelight/`. So serving this means creating that user-site repository.

Contents, once the Team ID is known:

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["<TeamID>.com.colewilliams.firelight"],
        "components": [{ "/": "/firelight/join*" }]
      }
    ]
  }
}
```

Two GitHub Pages details that waste an afternoon if missed:

- Jekyll ignores any directory starting with a dot, so `.well-known` is not
  published unless the repo has a `.nojekyll` file at its root.
- The file has no extension and must come back as JSON. Pages serves unknown
  types as `application/octet-stream`; Apple's CDN has tolerated that for
  years, but if the association refuses to validate this is the first thing
  to check.

## 2. The capability

`com.apple.developer.associated-domains` has to be on the App ID and in
`Firelight.entitlements` as `applinks:scwill12.github.io`. Unlike the other
capabilities, Xcode's automatic signing will not add this one on its own —
it has to be ticked in the developer portal first.

Worth remembering from CarPlay: **an entitlement in the file that the App ID
does not carry fails provisioning outright**. Add the capability first, then
the entitlement.

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
