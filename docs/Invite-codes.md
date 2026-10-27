# Invitation codes

## Bottom line

- An invitation is a **pasteable code**, not a link: `FL1eNq…`, about 110
  characters. Nothing is hosted, no domain is involved, and no link can rot.
- The code carries a **temporary** password the admin never sees. The
  invitation screen trades it for one the invited person chooses, and
  Audiobookshelf invalidates every other session for that account when a
  password changes — so a redeemed code is spent.
- The window before redemption is the real limit. Until then the code *is*
  the account. That is why invited accounts get no update, delete or upload
  permission, and why codes expire.

## Why not a link

A tappable `https://` link and an App Store fallback both need a domain to
host a landing page on. A static page that receives nothing is still a page
the author owns, pointed at by other people's invitations, and it breaks every
unredeemed invitation if it ever moves. For a client whose whole premise is
that there are no servers of ours, that is the wrong trade.

A `firelight://` scheme link would need no hosting, but most messaging apps do
not make custom schemes tappable and it does nothing at all without the app
installed — the worst of both.

The code costs one extra step. The message has to say "install Firelight"
regardless, so "install Firelight and paste this" is the same instruction.

## What is in the code

Four fields, because every byte is a character somebody pastes:

| | |
| --- | --- |
| `u` | the server's URL, sub-path and all |
| `n` | the username that was created |
| `p` | the temporary password |
| `e` | expiry, epoch seconds |

The server's name and the person's name are **not** carried. They are read
from the server after the code is redeemed, which makes the code about forty
characters shorter and the greeting more accurate than anything the admin
could have typed.

Encoding is base64url of compact JSON — **encoding, not encryption**. Whoever
holds the code holds the credential until it is redeemed. Compression was
tried and removed: at this size zlib saved three characters and added a way to
fail.

## Creating the account

Verified against the Audiobookshelf source, not assumed:

- `POST /api/users` takes `username` and `password`, and **defaults
  `isActive` to false** — an invited account that does not set it explicitly
  silently cannot sign in.
- A plain `user` already defaults to exactly the right permissions: `download`
  true, and `update`, `delete`, `upload` and `createEreader` all false. They
  are set explicitly anyway, so a future change to the server's defaults
  cannot quietly widen them.
- `PATCH /api/me/password` takes `{password, newPassword}`, rejects guest
  accounts with 403 — so invitations create `user`, never `guest` — and calls
  `invalidateJwtSessionsForUser` on success, which is what makes redemption
  evict anyone else who used the code. Sending `x-refresh-token` returns fresh
  tokens in the body, so the session survives the change.

## What is not built yet

The code format and its tests are done. Still to come: the two endpoints, the
invitation screen, and the admin flow that creates the account and produces
the code.
