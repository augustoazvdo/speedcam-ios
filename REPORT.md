# SpeedCam v1 implementation report

## Build and tests

- Debug simulator build: passed with `xcodebuild build` on iPhone 18 Pro / iOS 27.2; the final full test run also compiled the final Debug sources.
- Full unit and UI suite on iPhone 18 Pro / iOS 27.2: 126 unit tests passed; 25 UI tests passed and AC-131 was skipped because Simulator permissions had already been resolved; 0 failures (151 passed, 1 skipped total). The AC-136 zoom option and view-model tests passed.
- Release simulator build: passed. `scripts/check-release.sh` found no `SyntheticFrameSource`, `SimulatedLocationProvider`, or `AutoRecordRunner` symbols/strings in the Release binary.

## Exported sample

- Clip: `artifacts/sample.mov` (playable QuickTime movie, exported by the Debug auto-record hook).
- Frame: `artifacts/sample-frame.png` (frame at 2 seconds, 1080×1920). Visual inspection confirms the semicircular purple-to-blue gauge, `50 km/h`, unlabeled radial ticks, and bottom-left placement. The gauge itself has no numeric endpoints, GPS or date/time; the synthetic camera's separate test pattern still includes its own frame counter and clock in the background.

## Traceability

`scripts/check-traceability.sh`: **PASS** — 70 ACs total; 65 covered by automated tests and 5 by documented manual checks; 152 test functions; no unknown AC references or untagged tests; no open questions. Remaining assumptions are ASM-001 through ASM-020. The audit reports T-062, T-063, and T-080 unchecked, so T-080 remains open because its “all tasks done” condition is not met.

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

## Rear camera zoom controls (AC-136)

- The capture session prefers the device's rear virtual triple/dual camera and falls back to dual-wide, dual, or wide-angle. Zoom chips come from the camera's supported minimum, 1× when supported, and virtual-camera switch-over factors, with an iOS 18+ display multiplier when available. A selection ramps the capture device zoom and gives selection haptic feedback; the chips stay over the preview in both orientations.
- AC-136 tests were written first and initially failed to compile because `CameraZoomOption` did not exist. After implementation, option-range/label tests and the view-model selection/haptic test passed. Full simulator suite passed as reported above.
- ASM-020 records an AVFoundation limitation: it does not expose the full native Camera preset list (including model-specific crop presets). Physical iPhone verification is still needed to compare the offered labels and actual lens changes with Camera.app, especially on iPhone 15 Pro Max. The Simulator has no camera hardware.

## Assumptions and remaining work

- ASM-019 is retired: numeric gauge endpoints were removed at the user's request. GPS/date text was also removed from the gauge per AC-135; GPS status remains in app status/accessibility UI.
- ASM-020 documents the limit of public AVFoundation APIs for matching every Camera.app zoom preset; the physical lens-selection check is pending.
- ASM-018 documents that the configured iOS 27.2 simulator supplies invalid speed accuracy for the requested `simctl location` route. AC-092 therefore remains unverified at 50 km/h; the app correctly shows `--` / `GPS weak` rather than fabricating a reading.
- T-063 remains open. An iPhone 15 Pro Max is paired and available, and a local Apple Development identity was found. Device signing failed because Xcode has no connected Apple Developer account for that team and no matching app provisioning profile. No signed app was installed, and the 10-minute recording, dropped-frame rate, per-frame overlay, and preview latency were not measured.
- T-074 is complete. The fresh pt-BR simulator test captured camera, microphone, and location prompts in the xcresult. The real Photos add-only prompt was triggered by a synthetic recording and visually confirmed in Portuguese at `build/photos-permission-ptbr.png`; it was left unanswered.
- T-062 and T-063 remain open; consequently T-080 is also open even though the traceability audit passes its coverage checks. No open spec questions remain.
- T-090/T-091, T-092/T-093 and T-094/T-095 are complete. The AC-135 and AC-134 tests were run red before their renderer changes; renderer tests and the auto-record saved-frame test passed. The latest full suite has 147 passes and the unrelated AC-131 simulator prompt failure above. Debug and Release builds passed; the Release DEBUG-hook symbol/string scan passed.
