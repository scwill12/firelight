# Contributing to Firelight

Thanks for considering it. A few things worth knowing before you start.

## The spec is the contract

`SPEC.md` describes what Firelight is meant to be. `PROGRESS.md` records what
is built, what is verified, and every decision that departed from the spec
along with why. If you change behaviour the spec describes, update both.

## Before you open a pull request

```bash
scripts/build.sh          # must be clean: no errors, no new warnings
```

- **Every target builds.** The app, the widgets and the share extension.
- **Every test passes.** If you fixed a bug, add the test that would have
  caught it.
- **No hard-coded user-facing strings.** They all live in a String Catalog.
  Package modules use `L("…")`; app and extension targets use their own
  catalogs.
- **No hard-coded numbers in UI.** Spacing, radius, colour and motion come from
  `DesignSystem`.
- **Never edit `Firelight.xcodeproj`.** It is generated from `project.yml`.

## Things that will get a pull request sent back

- **Logging a token, a password, or a full server address.** Use `Redaction`.
  These are people's private servers.
- **Moving a user's position without asking** when the jump is large. The rule
  lives in `ProgressConflictResolver` and is covered by tests. It is the single
  most important behaviour in the app.
- **A feature without its empty, loading, error and offline states.** Offline
  is a normal condition here, not an error.
- **Guessing at the Audiobookshelf API.** Check the endpoint against
  [the source](https://github.com/advplyr/audiobookshelf) and record anything
  surprising in `CLAUDE.md`. `scripts/probe-abs.py` checks a running server
  against what the code assumes.
- **A dependency that is not MIT, BSD, Apache 2.0, MPL 2.0 or zlib.**

## Translations

Every string is in a String Catalog, ready for Weblate. Please do not hand-edit
`.xcstrings` for languages other than English — the catalogs are regenerated
from source.

## Reporting a bug

`Settings → Export diagnostics` produces a report with no address, username or
token in it. Attaching it helps enormously.
