#!/usr/bin/env python3
"""Copies the StoreKit configuration into each scheme's Test action.

XcodeGen writes `storeKitConfiguration` into a scheme's **Run** action only.
A UI test launched by `xcodebuild test` is started from the *Test* action,
which does not inherit it, so StoreKit hands back no products: the tip jar
shows "The App Store isn't reachable right now" and the screenshot run has
nothing to photograph.

This copies the reference across after generation. It is post-processing of
generated XML, which is a thing that normally breaks silently when the
generator's output changes — so this one is written to **fail loudly**
instead. If it cannot find what it expects, it exits non-zero and says why,
rather than leaving a scheme that looks fine and behaves wrong.

Run by `scripts/build.sh generate`; safe to run twice.
"""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCHEMES = ROOT / "Firelight.xcodeproj/xcshareddata/xcschemes"

# The whole element, however XcodeGen chooses to wrap it.
REFERENCE = re.compile(
    r"<StoreKitConfigurationFileReference\b.*?(?:/>|</StoreKitConfigurationFileReference>)",
    re.S,
)


def action(xml: str, name: str) -> re.Match[str] | None:
    return re.search(rf"<{name}\b.*?</{name}>", xml, re.S)


# Xcode resolves a scheme's StoreKit identifier relative to the directory the
# .xcscheme sits in, which is three levels inside the repository:
#   Firelight.xcodeproj/xcshareddata/xcschemes/X.xcscheme
# XcodeGen writes "../../App/Firelight.storekit", one level short, which
# resolves inside the .xcodeproj bundle and silently finds nothing. That is
# why the tip jar showed no products even when running from Xcode.
CORRECT_PREFIX = "../../../"
WRONG_PREFIX = "../../"


def fix_identifier(element: str) -> str:
    if f'identifier = "{CORRECT_PREFIX}' in element:
        return element
    return element.replace(
        f'identifier = "{WRONG_PREFIX}', f'identifier = "{CORRECT_PREFIX}', 1
    )


def patch(path: pathlib.Path) -> bool:
    """Returns True when the file was changed."""
    xml = path.read_text()

    launch = action(xml, "LaunchAction")
    if launch is None:
        return False
    found = REFERENCE.search(launch.group(0))
    if found is None:
        # No StoreKit configuration on this scheme at all; nothing to copy.
        return False

    element = fix_identifier(found.group(0))
    changed = False
    if element != found.group(0):
        xml = xml.replace(found.group(0), element, 1)
        changed = True
        launch = action(xml, "LaunchAction")
        assert launch is not None

    test = action(xml, "TestAction")
    if test is None:
        raise SystemExit(
            f"{path.name}: has a StoreKit configuration but no TestAction to copy it into. "
            "XcodeGen's output has changed shape; update scripts/patch_schemes.py."
        )
    if REFERENCE.search(test.group(0)):
        if changed:
            path.write_text(xml)
        return changed

    # Insert just before the Test action closes, matching its indentation.
    body = test.group(0)
    closing = "</TestAction>"
    if closing not in body:
        raise SystemExit(f"{path.name}: TestAction is not closed as expected.")
    patched_action = body.replace(closing, f"      {element}\n   {closing}", 1)
    path.write_text(xml.replace(body, patched_action, 1))
    return True


def main() -> None:
    if not SCHEMES.is_dir():
        raise SystemExit(f"No schemes at {SCHEMES}. Run xcodegen first.")

    changed = []
    for scheme in sorted(SCHEMES.glob("*.xcscheme")):
        if patch(scheme):
            changed.append(scheme.stem)

    if changed:
        print(f"  StoreKit configuration fixed up for: {', '.join(changed)}")


if __name__ == "__main__":
    main()
