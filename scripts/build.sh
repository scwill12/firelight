#!/usr/bin/env bash
# Builds and tests everything. Run from anywhere.
#
#   scripts/build.sh            generate, build every target, run the tests
#   scripts/build.sh generate   regenerate Firelight.xcodeproj from project.yml
#   scripts/build.sh build      build the app, widgets and share extension
#   scripts/build.sh watch      build the watch app
#   scripts/build.sh test       run the unit tests
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PROJECT="Firelight.xcodeproj"
SCHEME="Firelight"
WATCH_SCHEME="FirelightWatch"
SIM_NAME="Firelight-Test"
SIM_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"
SIM_RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-26-4"

# Only the lines worth reading. Full logs stay in DerivedData.
filter() {
  grep -E "error:|warning:.*\.swift|BUILD (SUCCEEDED|FAILED)|TEST (SUCCEEDED|FAILED)|Testing failed|✘|tests in .* suites" || true
}

generate() {
  command -v xcodegen >/dev/null || { echo "xcodegen not found: brew install xcodegen"; exit 1; }
  xcodegen generate
  # XcodeGen puts the StoreKit configuration on the Run action only, and a UI
  # test is launched from the Test action. Without this the tip jar has no
  # products under `xcodebuild test`.
  python3 "$(dirname "$0")/patch_schemes.py"
}

simulator_id() {
  local existing
  existing="$(xcrun simctl list devices -j | python3 -I -c '
import json,sys
data = json.load(sys.stdin)["devices"]
for runtime, devices in data.items():
    for device in devices:
        if device["name"] == "'"$SIM_NAME"'" and device["isAvailable"]:
            print(device["udid"]); raise SystemExit
')"
  if [ -n "$existing" ]; then echo "$existing"; return; fi
  xcrun simctl create "$SIM_NAME" "$SIM_TYPE" "$SIM_RUNTIME"
}

build_app() {
  echo "==> Building app, widgets and share extension"
  xcodebuild build -project "$PROJECT" -scheme "$SCHEME" \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | filter
}

build_watch() {
  echo "==> Building watch app"
  # Needs the watchOS simulator platform installed (Xcode > Settings > Components).
  xcodebuild build -project "$PROJECT" -scheme "$WATCH_SCHEME" \
    -destination 'generic/platform=watchOS Simulator' \
    -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | filter
}

run_tests() {
  local sim
  sim="$(simulator_id)"
  echo "==> Testing on $sim"
  xcodebuild test -project "$PROJECT" -scheme "$SCHEME" \
    -destination "id=$sim" -configuration Debug 2>&1 | filter
}

case "${1:-all}" in
  generate) generate ;;
  build)    build_app ;;
  watch)    build_watch ;;
  test)     run_tests ;;
  all)      generate; build_app; run_tests ;;
  *)        echo "usage: $0 [generate|build|watch|test|all]"; exit 1 ;;
esac
