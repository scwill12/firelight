# The four tip products

**Created.** All four exist on the app record as consumables, with names,
descriptions and US prices read straight out of `App/Firelight.storekit`, so
the store and the app cannot disagree. Verified by reading them back from
Apple.

They sit in `MISSING_METADATA` until each has a review screenshot, which is
the one part that has to be done by hand — see below.

To re-run after editing the StoreKit file (idempotent; it leaves anything
that already exists alone):

```bash
python3 scripts/appstore_tips.py            # dry run
python3 scripts/appstore_tips.py --apply
```

The reference below is what was created.


Paste-ready values for App Store Connect → Monetization → In-App Purchases.
Every one is taken from `App/Firelight.storekit`, which is what the app asks
StoreKit for — so the store and the app agree by construction rather than by
someone retyping carefully.

**Type: Consumable**, all four. Not non-consumable, not a subscription: a tip
can be given more than once and restores nothing.

| Product ID | Reference Name | Display Name | Price | Description |
| --- | --- | --- | --- | --- |
| `com.colewilliams.firelight.tip.coffee` | Tip — Coffee | Coffee | 0.99 | A small thank you. |
| `com.colewilliams.firelight.tip.snack` | Tip — Snack | Snack | 2.99 | A slightly larger thank you. |
| `com.colewilliams.firelight.tip.lunch` | Tip — Lunch | Lunch | 4.99 | A generous thank you. |
| `com.colewilliams.firelight.tip.dinner` | Tip — Dinner | Dinner | 9.99 | A very generous thank you. |

Prices are the US tier nearest each figure; App Store Connect sets every other
storefront from it.

## Review screenshot — after the products exist

Each product needs one, 1024 × 1024 or larger, and a single shot of the tip
jar serves all four: the reviewer is checking that the purchase appears where
the listing says it does.

**Create the four products first, then take it.** Once they exist in App
Store Connect, a TestFlight or sandbox build loads them for real and the tip
jar fills in. Screenshot it there (⌘S in the Simulator, or the device), crop
square — App Store Connect wants at least 1024 on the short edge and will not
crop for you.

The local `App/Firelight.storekit` does **not** work as a stand-in for this:
`Product.products(for:)` returns zero products and throws nothing, in both
`xcodebuild test` and a normal run. `CLAUDE.md` lists what has been ruled out.
It is not worth fighting, because creating the products is a step the release
needs regardless, and it solves this as a side effect.

## Review notes, per product

> A tip. Firelight is free and has no paid tier — this unlocks nothing and
> changes nothing about the app. It exists only for people who want to
> support the work.

That is worth stating plainly on every one. A consumable that appears to buy
nothing is the kind of thing a reviewer stops on, and the honest explanation
is also the correct one.

## Two things that get this rejected

1. **Submit them with the first build.** A binary that references in-app
   purchases which are not yet "Ready to Submit" fails review. Get all four
   through to that state *before* uploading.
2. **Do not imply they unlock anything.** `TipJar.swift` opens with a comment
   saying a tip jar that quietly gates a feature is a paywall with better
   manners. Keep the store descriptions as plain as the code is.

## Testing them without App Store Connect

`App/Firelight.storekit` is wired into the Firelight scheme's run action, so
the tip jar loads all four locally with no account, no sandbox user and no
network. Purchases there are fake and free.
