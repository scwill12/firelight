# The four tip products

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

## Review screenshot

Each product needs one, 1024 × 1024 or larger. `docs/screenshots/06-tip-jar.png`
shows all four in the app, which is what the reviewer is checking — that the
purchase exists where the listing says it does. The same image serves all four
products.

Crop it square before uploading; App Store Connect wants at least 1024 on the
short edge and will not do the cropping for you.

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
