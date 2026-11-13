#!/usr/bin/env bash
# Build and run tests on the iOS 27.2 "iPhone 18 Pro" simulator.
# Usage: scripts/test.sh [xcodebuild args...]   e.g. scripts/test.sh -only-testing:SpeedCamTests
set -euo pipefail
cd "$(dirname "$0")/.."
DEST="platform=iOS Simulator,name=iPhone 18 Pro,OS=27.2"
/opt/homebrew/bin/xcodegen generate --quiet
xcodebuild -project SpeedCam.xcodeproj -scheme SpeedCam -destination "$DEST" \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO test "$@"
