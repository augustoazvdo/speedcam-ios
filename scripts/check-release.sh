#!/usr/bin/env bash
# AC-103: Release must contain no DEBUG camera/location/auto-record hooks.
set -euo pipefail
cd "$(dirname "$0")/.."
device=${1:-EFCA41B6-6189-4E84-B4F4-7254F18A6926}
/opt/homebrew/bin/xcodegen generate --quiet
xcodebuild -project SpeedCam.xcodeproj -scheme SpeedCam -configuration Release \
  -destination "id=$device" -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build

binary=build/DerivedData/Build/Products/Release-iphonesimulator/SpeedCam.app/SpeedCam
test -x "$binary"
for symbol in SyntheticFrameSource SimulatedLocationProvider AutoRecordRunner; do
  if { nm -a "$binary" 2>/dev/null | xcrun swift-demangle; strings -a "$binary"; } | grep -q "$symbol"; then
    echo "DEBUG-only symbol/string present in Release: $symbol" >&2
    exit 1
  fi
done
echo "Release has no SyntheticFrameSource, SimulatedLocationProvider or AutoRecordRunner symbols/strings."
