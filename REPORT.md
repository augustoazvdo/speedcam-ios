# SpeedCam v1 implementation report

## Build and tests

- Debug simulator build: passed with `xcodebuild build` on iPhone 18 Pro / iOS 27.2.
- Full unit and UI suite: passed with `scripts/test.sh -parallel-testing-enabled NO` on iPhone 18 Pro / iOS 27.2. Unit: 122 passed, 0 failed. UI: 25 passed, 1 skipped, 0 failed. The skip is AC-131 on the main simulator because SpringBoard is English; the dedicated pt-BR simulator run passed.
- Release simulator build: passed. `scripts/check-release.sh` found no `SyntheticFrameSource`, `SimulatedLocationProvider`, or `AutoRecordRunner` symbols/strings.

## Exported sample

- Clip: `artifacts/sample.mov` (playable QuickTime movie, exported by the Debug auto-record hook).
- Frame: `artifacts/sample-frame.png` (frame at 2 seconds, 1080×1920). Visual inspection confirms `50 km/h`, green GPS indicator, timestamp, and overlay in the bottom-left corner.

## Traceability

`scripts/check-traceability.sh`: **PASS** — 67 ACs total; 62 covered by automated tests and 5 by documented manual checks; 148 test functions; no unknown AC references or untagged tests; no open questions. Remaining assumptions are ASM-001 through ASM-018. The audit reports T-062, T-063, and T-080 unchecked, so T-080 remains open because its “all tasks done” condition is not met.

## Security checks

- Network and third-party code: `scripts/check-privacy.sh` found no network APIs or third-party dependency declarations; no analytics, crash-reporting, or remote-config SDKs are present.
- Permissions and localization: the built Info.plist contains specific camera, microphone, location When In Use, and Photos add-only descriptions; `scripts/check-localization.sh` verified English and pt-BR strings. No Always-location key or location background mode is present.
- Location lifecycle: privacy checks verified `allowsBackgroundLocationUpdates = false`; unit coverage verifies foreground-only updates and stopping on background.
- Photos and local clips: verified `.addOnly`, pending clips retained on failure and deleted only after successful save, and sandbox clips excluded from backup. Unit tests cover success, failure, and retry.
- Release hooks: Release build and `nm`/`strings` scan confirmed all three DEBUG-only hooks are absent.
- Secrets/signing files: tracked-source key/token and personal `DEVELOPMENT_TEAM` scan was clean; no signing certificates or provisioning files are tracked.

## Premium-feel checks

- Feedback after actions: tests verify haptics for record/stop and corner selection; UI tests verify the recording dot and timer, “Saving…”, saved confirmation, and thumbnail.
- Obvious next step: `test_AC111_oneNextStepPerState` and `test_AC113_designedStatesHaveIconTextAndOneAction` passed.
- Specific errors with one action: `test_AC078_everyNoticeHasSpecificMessageAndOneAction` passed, alongside the UI checks for permission, GPS, and Photos errors.

## Assumptions and remaining work

- No new ASM was added in this continuation. The implementation records ASM-001–ASM-018; ASM-018 documents that the configured iOS 27.2 simulator supplies invalid speed accuracy for the requested `simctl location` route. AC-092 therefore remains unverified at 50 km/h; the app correctly shows `--` / `GPS weak` rather than fabricating a reading.
- T-063 remains open. An iPhone 15 Pro Max is paired and available, and a local Apple Development identity was found. Device signing failed because Xcode has no connected Apple Developer account for that team and no matching app provisioning profile. No signed app was installed, and the 10-minute recording, dropped-frame rate, per-frame overlay, and preview latency were not measured.
- T-074 is complete. The fresh pt-BR simulator test captured camera, microphone, and location prompts in the xcresult. The real Photos add-only prompt was triggered by a synthetic recording and visually confirmed in Portuguese at `build/photos-permission-ptbr.png`; it was left unanswered.
- T-062 and T-063 remain open; consequently T-080 is also open even though the traceability audit passes its coverage checks. No open spec questions remain.
