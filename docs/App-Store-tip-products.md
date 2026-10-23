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

## Review screenshot — take this one by hand

Each product needs one, 1024 × 1024 or larger, and one shot of the tip jar
serves all four: the reviewer is checking that the purchase exists where the
listing says it does.

**The automated run cannot take it**, and not for the reason it first
appeared. Two things were wrong and only one of them was fixable:

1. XcodeGen writes the StoreKit configuration into the scheme's *Run* action
   only. `scripts/patch_schemes.py` now copies it into the Test action too.
2. XcodeGen also wrote the path one level short —
   `../../App/Firelight.storekit`, which resolves *inside* the `.xcodeproj`
   rather than into the repository, so it pointed at nothing. The same script
   corrects it to `../../../`.

With both fixed the products still do not load under `xcodebuild test`: a
StoreKit Testing configuration is not applied to the app-under-test when a UI
test runner launches it. That one is Apple's, not ours.

Running the app from Xcode uses the Run action directly, which is the path
that should work — the configuration there now points at a file that exists,
where before it did not. **Not verified by me**, because driving Xcode's UI is
outside what I can do; if the tip jar is still empty on ⌘R, say so and the
next thing to check is Edit Scheme → Run → Options → StoreKit Configuration.

To take the shot:

1. Open the project in Xcode and press ⌘R.
2. Settings → Support Firelight. All four tips load from
   `App/Firelight.storekit`, with no account and no sandbox user.
3. Screenshot it (⌘S in the Simulator), then crop square — App Store Connect
   wants at least 1024 on the short edge and will not crop for you.

`scripts/patch_schemes.py` runs as part of `scripts/build.sh generate`. It
fails loudly rather than silently if XcodeGen's output changes shape, which is
the usual failure mode for post-processing generated files.

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
