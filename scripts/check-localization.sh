#!/usr/bin/env bash
# AC-131/132/133: catalogs match source and compile into the shipped app.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import json, plistlib, re
from pathlib import Path

source = Path('SpeedCam/App/L10n.swift').read_text()
keys = set(re.findall(r'String\(localized: "((?:[^"\\]|\\.)*)"\)', source))
catalog = json.loads(Path('SpeedCam/Resources/Localizable.xcstrings').read_text())['strings']
assert set(catalog) == keys, f'Localizable.xcstrings mismatch: missing={sorted(keys-set(catalog))}, stale={sorted(set(catalog)-keys)}'
for key, entry in catalog.items():
    locs = entry.get('localizations', {})
    for locale in ('en', 'pt-BR'):
        value = locs.get(locale, {}).get('stringUnit', {}).get('value', '')
        assert value.strip(), f'{key}: missing {locale} value'

info = json.loads(Path('SpeedCam/Resources/InfoPlist.xcstrings').read_text())['strings']
usage = {'NSCameraUsageDescription', 'NSMicrophoneUsageDescription',
         'NSLocationWhenInUseUsageDescription', 'NSPhotoLibraryAddUsageDescription'}
assert usage <= set(info), f'InfoPlist.xcstrings missing {sorted(usage-set(info))}'
for key in usage:
    for locale in ('en', 'pt-BR'):
        value = info[key].get('localizations', {}).get(locale, {}).get('stringUnit', {}).get('value', '')
        assert len(value) > 40, f'{key}: missing/specific {locale} value'

for path in Path('SpeedCam').rglob('*.swift'):
    if path.name == 'L10n.swift':
        continue
    text = path.read_text()
    if re.search(r'\b(?:Text|Button|Label|accessibilityLabel|accessibilityHint)\s*\(\s*"', text):
        raise SystemExit(f'hard-coded user-facing literal in {path}')

compiled = Path('build/DerivedData/Build/Products/Release-iphonesimulator/SpeedCam.app/pt-BR.lproj/InfoPlist.strings')
assert compiled.is_file(), f'missing compiled Portuguese InfoPlist.strings: {compiled}'
values = plistlib.loads(compiled.read_bytes())
assert usage <= set(values), f'compiled Portuguese InfoPlist.strings missing {sorted(usage-set(values))}'
print(f'{len(keys)} UI keys have en + pt-BR; usage catalog and compiled Portuguese prompt strings are complete.')
PY
