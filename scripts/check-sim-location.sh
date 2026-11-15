#!/usr/bin/env bash
# AC-092 manual check: drive real CoreLocationProvider from simctl at ~50 km/h.
set -euo pipefail
cd "$(dirname "$0")/.."

device=${1:-EFCA41B6-6189-4E84-B4F4-7254F18A6926}
app="build/DerivedData/Build/Products/Debug-iphonesimulator/SpeedCam.app"
check_dir=$(mktemp -d /tmp/speedcam-ac092.XXXXXX)
export_dir="$check_dir/export"
frame="$check_dir/location-overlay.png"

/opt/homebrew/bin/xcodegen generate --quiet
xcodebuild -project SpeedCam.xcodeproj -scheme SpeedCam \
  -destination "id=$device" -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
xcrun simctl install "$device" "$app"
xcrun simctl privacy "$device" grant location com.augusto.speedcam
xcrun simctl location "$device" clear
trap 'xcrun simctl location "$device" clear >/dev/null 2>&1 || true' EXIT
xcrun simctl location "$device" start --speed=14 --interval=1 \
  37.000000,-122.000000 37.100000,-122.000000
xcrun simctl launch --terminate-running-process "$device" com.augusto.speedcam \
  -SpeedCamSkipOnboarding YES \
  -SpeedCamSyntheticCamera YES \
  -SpeedCamAutoRecordSeconds 10 \
  -SpeedCamExportPath "$export_dir" \
  -SpeedCamFakePhotos success

deadline=$((SECONDS + 30))
clip=""
while (( SECONDS < deadline )); do
  clip=$(find "$export_dir" -maxdepth 1 -type f -name '*.mov' -print -quit 2>/dev/null || true)
  [[ -n "$clip" ]] && break
  sleep 1
done
[[ -n "$clip" ]] || { echo "No exported clip; check the simulator console/logs." >&2; exit 1; }
scripts/extract-frame.sh "$clip" 7 "$frame"
echo "Inspect the frame for approximately 50 km/h and GPS: $frame"
