#!/usr/bin/env bash
# AC-100/101/102/105: privacy and dependency guardrails.
set -euo pipefail
cd "$(dirname "$0")/.."

if rg -n 'URLSession|NWConnection|Network\.framework|import Network' SpeedCam; then
  echo "Network API found in app sources" >&2
  exit 1
fi
if rg -n 'packages:|package\.url|pod |Carthage|Package\.swift' project.yml SpeedCam; then
  echo "Third-party dependency declaration found" >&2
  exit 1
fi

python3 - <<'PY'
import plistlib
from pathlib import Path
p = plistlib.loads(Path('build/DerivedData/Build/Products/Release-iphonesimulator/SpeedCam.app/Info.plist').read_bytes())
keys = ('NSCameraUsageDescription', 'NSMicrophoneUsageDescription',
        'NSLocationWhenInUseUsageDescription', 'NSPhotoLibraryAddUsageDescription')
for key in keys:
    value = p.get(key)
    assert isinstance(value, str) and len(value) > 40, f'missing/specific usage description: {key}'
for key in ('NSLocationAlwaysUsageDescription', 'NSLocationAlwaysAndWhenInUseUsageDescription', 'UIBackgroundModes'):
    assert key not in p, f'forbidden plist key: {key}'
assert {'en', 'pt-BR'} <= set(p.get('CFBundleLocalizations', []))
print('Built Info.plist: four specific usage descriptions, en + pt-BR, no Always/background keys.')
PY

rg -q 'accessLevel: PHAccessLevel = \.addOnly' SpeedCam/Library/PhotoLibrarySaver.swift
rg -q 'authorizationStatus\(for: Self\.accessLevel\)' SpeedCam/Library/PhotoLibrarySaver.swift
rg -q 'isExcludedFromBackup = true' SpeedCam/Library/ClipStore.swift
rg -q 'case \.background' SpeedCam/UI/CameraViewModel.swift
rg -q 'manager\.allowsBackgroundLocationUpdates = false' SpeedCam/Location/CoreLocationProvider.swift
echo "Source checks: Photos add-only, clips excluded from backup, location foreground-only."
