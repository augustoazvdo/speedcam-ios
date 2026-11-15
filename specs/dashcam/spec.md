# SpeedCam — Dashcam recording with burned-in speedometer

- **Feature:** dashcam
- **Status:** Approved (open questions resolved 2026-11-13)
- **Platform:** Native iPhone app, SwiftUI + AVFoundation + CoreLocation, min iOS 17, no third-party dependencies
- **Owner:** Augusto Azevedo
- **Last updated:** 2026-11-13

## 1. Summary

SpeedCam records video like the native Camera app. A speedometer overlay (GPS speed and unit only) is composited into every video frame in real time, so the overlay is part of the saved file and visible anywhere the clip is shared. Built for drivers with the phone in a car mount (usually landscape). Default unit is km/h with an mph toggle.

Out of scope for v1: loop recording / segmenting / auto-delete (Q-001), GPS coordinates, heading or street name in the overlay (Q-002), in-app clip library (Q-004), speed-limit / over-speed warning (Q-006), crash (g-sensor) detection, maps/route overlay, cloud upload, editing, photo capture, front camera, Apple Watch, CarPlay.

## 2. User stories

- **US-01 Permissions.** As a driver opening SpeedCam for the first time, I want to understand and grant the permissions it needs, and recover easily if I denied one, so I can start recording.
- **US-02 Live preview.** As a driver, I want a full-screen camera preview with the speedometer shown live, so I can see exactly what will be recorded.
- **US-03 Record.** As a driver, I want to start and stop recording with one tap and always know whether I am recording.
- **US-04 Burned-in overlay.** As a driver, I want speed and unit shown in a clear speedometer burned into the video file, so anyone I share the clip with sees them.
- **US-05 Honest speed.** As a driver, I want the speed to be smooth and truthful, showing "--" when GPS can't give a reliable value instead of a made-up number.
- **US-06 Orientation.** As a driver, I want recording to work in portrait and landscape with the overlay upright and readable in the saved video.
- **US-07 Save & review.** As a driver, I want clips saved to Photos automatically when I stop, with confirmation and a quick way to open the last clip.
- **US-08 Failures.** As a driver, I want recording failures (storage, calls, backgrounding, permissions, heat, no GPS) handled safely, with no lost footage and a clear next step.
- **US-09 Settings.** As a driver in Brazil, I want km/h by default and an mph option that is remembered.
- **US-10 Testability.** As the developer, I want the whole pipeline to run on the iOS Simulator (no camera) using a synthetic camera and simulated location, producing a real video file I can inspect.
- **US-11 Privacy & security.** As a driver, I want my clips and location to stay on my phone.
- **US-12 Overlay corner.** As a driver, I want to choose which corner of the video the speedometer sits in, so it doesn't cover the part of the road I care about.
- **US-13 Language.** As a driver in Brazil, I want the app in Portuguese (or English, following my phone's language).

## 3. Acceptance criteria

All criteria are observable from the UI, the saved file, the Photos library, the app bundle, or the repository.

### US-01 Permissions

- **AC-001** Given a fresh install, When the app launches, Then an onboarding screen lists Camera, Microphone, Location (While Using) and Photos (add only) with a one-line reason each and a single "Continue" button; no system prompt appears before the user taps it.
- **AC-002** Given the onboarding screen, When the user taps "Continue", Then system prompts for camera, microphone, location When In Use, and photo-library add-only are shown one after another, and the app never requests "Always" location or full photo-library read access.
- **AC-003** Given camera permission is denied, When the main screen is shown, Then the preview area shows a designed denied state ("Camera access is off. SpeedCam needs it to record.") with one "Open Settings" button that opens the app's page in iOS Settings, and the record button is disabled.
- **AC-004** Given microphone permission is denied and camera is granted, When the user records, Then recording works without audio and a persistent badge "No audio — Mic off" is shown; tapping it offers "Open Settings".
- **AC-005** Given location permission is denied, When the main screen is shown, Then the speedometer shows "--", recording is still allowed, and a banner "Location is off — speed won't be recorded" offers "Open Settings".
- **AC-006** Given Photos add permission is denied, When a recording stops, Then the clip is kept in the app's local storage, and a message "Couldn't save to Photos — access is off" offers "Open Settings"; after access is granted and the app returns to the foreground, pending clips are saved to Photos automatically and confirmation is shown.
- **AC-007** Given the user returns from iOS Settings after granting a previously denied permission, When the app becomes active, Then the related denied state disappears without restarting the app.

### US-02 Live preview

- **AC-010** Given camera permission is granted, When the main screen is shown, Then the back wide camera preview fills the screen (aspect-fill, no letterbox bars) within 1.5 s on device.
- **AC-011** Given the preview is visible, When not recording, Then the speedometer overlay is shown live over the preview in the same position, size and style as it appears in the recorded file.
- **AC-012** Given the main screen, When idle, Then the record button, unit indicator, last-clip thumbnail (or an empty placeholder "No clips yet") and settings button are visible and reachable with one thumb. The settings sheet contains only the unit toggle (US-09) and the overlay corner picker (US-12).

### US-03 Record start/stop

- **AC-020** Given the app is idle with camera granted, When the user taps the record button, Then within 500 ms the button changes to a stop state, a pulsing red dot and an elapsed timer (MM:SS, H:MM:SS after 1 h) appear, and a medium haptic fires.
- **AC-021** Given recording is in progress, When the user taps stop, Then the timer stops, a haptic fires, a "Saving…" indicator shows until the file is finalized, and the button returns to the idle state.
- **AC-022** Given recording is in progress, When the device would normally auto-lock, Then the screen stays awake; When recording stops, Then normal auto-lock behaviour resumes.
- **AC-023** Given recording is in progress, When the user double-taps record quickly, Then exactly one start or stop action happens (debounced) and no empty or corrupt file is produced.

### US-04 Burned-in overlay

- **AC-030** Given a recording made with a known speed, When a frame is extracted from the saved file (ffmpeg or AVAssetImageGenerator), Then the frame shows only the speedometer with the speed number and unit ("km/h" or "mph"); GPS status and date/time are not burned into the frame.
- **AC-031** Given a recording, When the file is inspected, Then it contains one H.264 or HEVC video track at the capture resolution (1080p default) at ~30 fps and, if the mic is granted, one AAC audio track in sync with video (offset ≤ 100 ms).
- **AC-032** Given the speed changes during recording, When frames from different times are extracted, Then the overlay values in the frames match the speed reported at those times (within one smoothing window, ≤ 1 s lag).
- **AC-033** Given a 10-minute recording on a supported device, When the file is inspected, Then no more than 1% of expected frames are dropped and the overlay is present on every frame.
- **AC-034** Given recording, When the overlay is rendered, Then it remains legible on bright sky and dark night scenes (semi-opaque background plate behind text).

### US-05 Speed accuracy

- **AC-040** Given CLLocation reports speed −1 (invalid), When the overlay updates, Then it shows "--" (not 0 and not the last value after 3 s of invalid data).
- **AC-041** Given location updates with `horizontalAccuracy` > 50 m or `speedAccuracy` invalid/ > 5 m/s, When the speedometer updates, Then it shows "--"; the GPS indicator shows "weak" in the app's status/accessibility text, outside the burned-in speedometer.
- **AC-042** Given no valid location update for more than 3 s, When the speedometer updates, Then it shows "--"; the GPS indicator shows "no fix" in the app's status/accessibility text, outside the burned-in speedometer.
- **AC-043** Given a sequence of valid speeds with noise, When displayed, Then the value is smoothed (no jumps greater than the true change plus 3 km/h between consecutive displayed values at 1 Hz input) and rounded to a whole number.
- **AC-044** Given valid speed below 2 km/h, When displayed, Then it shows "0" (stationary jitter suppressed).
- **AC-045** Given the unit is km/h, When the speed is 13.89 m/s, Then the overlay shows "50"; Given mph, Then it shows "31".

### US-06 Orientation

- **AC-050** Given the device is in landscape (left or right) or portrait, When the user records, Then the saved video plays upright in Photos with the overlay upright and anchored to the same corner relative to the viewer.
- **AC-051** Given the device rotates during idle, When the UI updates, Then controls rotate/reposition to stay in the same logical positions (record button on the trailing/bottom edge nearest the thumb) with no layout jump.
- **AC-052** Given recording has started, When the device rotates, Then the recorded file keeps the orientation locked at start (no mid-clip rotation), and the on-screen controls still rotate for readability.

### US-07 Save & review

- **AC-060** Given a recording stopped normally and Photos add permission is granted, When finalization completes, Then the clip appears in the Photos library and a toast "✓ Saved to Photos" appears for ~2 s.
- **AC-061** Given a clip was saved, When the main screen is shown, Then the last-clip thumbnail shows that clip's first frame (generated from the local file before it is deleted); tapping it opens the Photos app. There is no in-app clip library or player (Q-004).
- **AC-062** Given the clip was saved to Photos successfully, When saving completes, Then the app's own copy is deleted from the sandbox (confirmed Q-007); Given saving failed, Then the app's copy is kept as pending (AC-006).

### US-08 Failure states

- **AC-070** Given free storage is below 500 MB, When the user taps record, Then recording does not start and an error "Not enough storage — free up space to record" with an "OK" action is shown.
- **AC-071** Given recording is in progress and free storage drops below 200 MB, When the threshold is crossed, Then the recording stops, the clip is finalized and saved, and the message "Recording stopped — storage almost full" is shown.
- **AC-072** Given recording is in progress, When a phone call or other audio/camera interruption begins, Then the clip so far is finalized as a playable file and saved, and on return the app shows "Recording stopped by a call — clip saved".
- **AC-073** Given recording is in progress, When the app goes to the background, Then the clip so far is finalized as a playable file and saved, and on return the app shows "Recording stopped when the app closed — clip saved".
- **AC-074** Given recording is in progress, When camera or location permission is revoked in Settings, Then camera revocation stops and saves the clip with an explanation and "Open Settings"; location revocation continues recording with "--" and the GPS-off banner.
- **AC-075** Given no GPS fix, When recording, Then recording proceeds with "--" in the speedometer and the app shows its non-blocking no-fix status; no blocking alert is shown.
- **AC-076** Given recording, When thermal state becomes `.serious`, Then a warning "Phone is hot — recording may stop" is shown; When `.critical`, Then the clip is finalized and saved with "Recording stopped — phone too hot".
- **AC-077** Given the app was killed or crashed mid-recording, When it is relaunched, Then any partially written clip that is playable is recovered to Photos (or reported as unrecoverable) and the user is told the outcome.
- **AC-078** Given any failure, When the app shows the error, Then the message names the specific cause and offers exactly one primary action.

### US-09 Settings

- **AC-080** Given a fresh install with any region, When the app launches, Then the unit is km/h.
- **AC-081** Given the user toggles the unit to mph, When the app is relaunched, Then the unit is still mph in the preview and in new recordings.
- **AC-082** Given recording is in progress, When the user taps the unit indicator, Then the unit changes immediately in the preview and the recorded overlay from that moment.

### US-10 Testability

- **AC-090** Given a Debug build launched with `-SpeedCamSyntheticCamera YES` (or on a Simulator with no camera), When the main screen is shown, Then a synthetic frame source supplies moving test frames (gradient + frame counter + clock) at 30 fps in place of the camera and the speedometer gauge is shown.
- **AC-091** Given a Debug build launched with `-SpeedCamSimulatedLocation <scenario>` (e.g. `constant50kmh`, `accelerate`, `invalid`, `noFix`), When recording, Then speeds follow the scenario deterministically.
- **AC-092** Given the Simulator with the CoreLocation provider, When `xcrun simctl location <device> start …` drives a route, Then the overlay shows a speed matching the route.
- **AC-093** Given a Debug build launched with `-SpeedCamAutoRecordSeconds 5 -SpeedCamExportPath <dir>` plus synthetic camera and simulated location, When launched on the Simulator, Then the app records 5 s and writes a playable `.mov` to the export directory (and logs its path); a frame extracted from it with ffmpeg or AVAssetImageGenerator visibly shows the overlay with the scenario speed.
- **AC-094** Given the UI test suite, When run with `xcodebuild test` on an iOS 27 Simulator ("iPhone 18 Pro"), Then a test starts and stops a recording via the UI, asserts the red dot, timer and "✓ Saved to Photos" (or the export file) appear, and a test extracts a frame and asserts non-background overlay pixels in the overlay region.

### US-11 Privacy & security

- **AC-100** Given the app is running in any flow, When network traffic is observed, Then the app makes no network requests (no analytics, crash reporting SDKs, or remote config).
- **AC-101** Given the built app's Info.plist, When inspected, Then `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSLocationWhenInUseUsageDescription` and `NSPhotoLibraryAddUsageDescription` are present with specific text, and no `NSLocationAlways*` key or `location` background mode is present.
- **AC-102** Given the app is in the background or not recording and not in foreground, When location services are inspected, Then the app is not receiving location updates (updates run only while the app is foreground; status bar shows no location arrow after leaving the app).
- **AC-103** Given a Release build, When the launch arguments for synthetic camera, simulated location or auto-record are passed, Then they have no effect and the synthetic/simulated code is not compiled into the binary.
- **AC-104** Given the repository, When scanned (e.g. `git grep` for keys/tokens, `.gitignore` review), Then it contains no secrets, API keys, provisioning profiles or signing certificates.
- **AC-105** Given recorded clips, When stored, Then they live only in the app's sandbox and the user's Photos library; nothing is uploaded or shared without an explicit user action.

### US-12 Overlay corner

- **AC-120** Given a fresh install, When the preview and a recording are shown, Then the overlay sits in the bottom-left corner.
- **AC-121** Given the settings sheet, When the user picks top-left, top-right, bottom-left or bottom-right, Then the live preview moves the overlay to that corner within 300 ms and a haptic confirms the choice.
- **AC-122** Given the user picked a corner, When a clip is recorded and a frame extracted, Then the overlay pixels are in that corner of the upright video, in portrait and landscape.
- **AC-123** Given the user picked a corner, When the app is relaunched, Then the same corner is still selected in settings, preview and new recordings.
- **AC-124** Given recording is in progress, When the user opens settings, Then the corner picker is disabled with the hint "Applies to the next recording" (ASM-013), and the current file's overlay does not move.

### US-13 Language

- **AC-130** Given the device language is Portuguese (Brazil), When any screen, banner, toast or error is shown, Then all user-facing text is in pt-BR (e.g. "✓ Salvo em Fotos"); Given English, Then it is in English; Given any other language, Then it is in English.
- **AC-131** Given the device language is pt-BR or English, When each system permission prompt appears, Then the camera, microphone, location and Photos usage strings are shown in that language (localized via `InfoPlist.xcstrings`).
- **AC-132** Given the repository, When `Localizable.xcstrings` and `InfoPlist.xcstrings` are inspected, Then every key has a translated, non-stale value for both `en` and `pt-BR`, and no user-facing string in code is a hard-coded literal outside the catalog.
- **AC-133** Given the device locale is pt-BR, When the speedometer and timer are rendered, Then the unit label stays "km/h" / "mph" and numbers use locale formatting; the speedometer has no date/time text.
- **AC-134** Given a speed is available, When the overlay is rendered, Then the speed and unit appear centered inside a semicircular gauge with a purple-to-blue arc and radial tick marks; numeric endpoint labels are omitted.
- **AC-135** Given GPS status or the current date/time changes, When the speedometer is rendered, Then its image contains only the gauge, speed number and unit; GPS status and date/time add no text or graphics.

### Premium feel (cross-cutting)

- **AC-110** Given any user action (record, stop, unit toggle, open thumbnail, open settings), When performed, Then visible feedback (state change, toast, or haptic) appears within 300 ms.
- **AC-111** Given any screen state (onboarding, idle, recording, saving, denied, no GPS, error), When shown, Then exactly one obvious next step is presented.
- **AC-112** Given portrait and landscape, When comparing screens, Then controls keep the same order, icons, and styling.
- **AC-113** Given the empty (no clips), permission-denied and GPS-offline states, When shown, Then each has a designed illustration/icon, a one-line explanation, and a single action — no blank areas or raw system errors.

## 4. Assumptions

- **ASM-001** Speed source is `CLLocation.speed` (m/s) from CoreLocation with `kCLLocationAccuracyBestForNavigation`; no OBD/Bluetooth integration.
- **ASM-002** Back wide camera only; 1080p @ 30 fps default, HEVC if supported else H.264, `.mov` container.
- **ASM-003** Overlay layout: semicircular speed gauge with the unit above the centered speed, purple-to-blue arc and radial ticks without numeric endpoint labels; no GPS status or date/time; placed in the user-selected corner (default bottom-left, US-12) with a fixed safe margin (~4% of the short side); size and style are fixed.
- **ASM-004** (retired by AC-135) The speedometer does not burn a timestamp into the video.
- **ASM-005** Recording is foreground-only; backgrounding stops and saves the clip (no background recording, which iOS does not permit for camera).
- **ASM-006** Smoothing: exponential moving average (α ≈ 0.5 at 1 Hz) on valid samples; accuracy thresholds 50 m horizontal and 5 m/s speed accuracy; 3 s staleness timeout; < 2 km/h shown as 0.
- **ASM-007** Clips have no max length beyond storage; one continuous file per recording, no loop recording (confirmed Q-001).
- **ASM-008** UI ships in English (development language) and pt-BR via String Catalogs (`Localizable.xcstrings`, `InfoPlist.xcstrings`), following the device language; any other language falls back to English (confirmed Q-005).
- **ASM-009** Orientation of the recorded file is locked at record start.
- **ASM-010** Debug-only test hooks are enabled via launch arguments and compiled out of Release with `#if DEBUG`.
- **ASM-011** Storage thresholds: 500 MB to start, 200 MB to auto-stop.
- **ASM-012** With add-only Photos access the app cannot read assets back, so the thumbnail is generated from the local file before deletion and is kept as a small JPEG in the sandbox; tapping it opens the Photos app (`photos-redirect://`), not the specific asset.
- **ASM-013** Overlay corner is locked at record start like orientation; changing it during recording applies from the next recording (preview shows the pending change with a hint).
- **ASM-014** (added during implementation) In AC-042, a "valid location update" means any CoreLocation update with a fix (`horizontalAccuracy` ≥ 0), whatever its speed validity. A stream of fixes with invalid speed or poor accuracy therefore shows "--" with "weak" (AC-040/AC-041), and "no fix" is shown only when no fix at all has arrived for more than 3 s. Both cases show "--", so no speed value is ever fabricated (R-08). The EMA restarts after any invalid, inaccurate or stale sample.
- **ASM-015** (added during implementation) Besides the arguments in design §6, DEBUG builds accept `-SpeedCamFakePermissions <kind=status,…>`, `-SpeedCamFakePhotos success|denied|fail` and `-SpeedCamFakeFreeMB <n>` so UI tests can drive denied, Photos-failure and low-storage states deterministically on the Simulator. They are compiled out of Release with the other hooks (R-04, AC-103).
- **ASM-016** (retired by AC-135) The earlier overlay included a device-local timestamp; the requested gauge-only style removes it from the saved pixels.
- **ASM-017** (added during implementation) AC-010 (aspect-fill, full screen) and AC-011 (overlay in the same position as in the file) conflict when the preview runs under the control bar: the plate in a bottom corner was cropped and hidden behind the controls. The preview therefore fills the whole camera area, aspect-fill with no letterbox bars, edge to edge and under the status area, but stops at the opaque control bar (bottom in portrait, trailing edge in landscape). The aspect ratio of that area is close to the 16:9 frame, so the plate is fully visible in every orientation.
- **ASM-018** (added during implementation) On the configured iOS 27.2 Simulator, `simctl location start --speed=14` emits fixes whose speed accuracy is invalid, so AC-041 correctly requires `--` / `GPS weak`; waiting longer does not make it valid. The built-in `Freeway Drive` scenario yields a valid speed but not a controllable 50 km/h value. Keep AC-041's filter; the AC-092 speed match remains unverified on Simulator and needs a simulator/runtime that supplies valid speed accuracy or a physical device.
- **ASM-019** (retired by the requested label removal) The numeric endpoint values from the reference are not shown; only the unlabeled radial ticks remain.

## 5. Questions (all resolved 2026-11-13 by Augusto)

No open questions remain; implementation is unblocked.

- **Q-001** Loop recording? — **Resolved:** No loop recording. One continuous clip per recording (ASM-007).
- **Q-002** Extra overlay data? — **Resolved and updated per user direction:** Show only the speedometer, speed and unit. No GPS status, timestamp, coordinates, heading or street name in the burned-in overlay.
- **Q-003** Overlay position? — **Resolved:** User picks the corner (top-left, top-right, bottom-left, bottom-right); default bottom-left; saved, shown in the live preview and burned into the file (US-12, AC-120–AC-124).
- **Q-004** Where clips live? — **Resolved:** Photos only. No in-app library (AC-061).
- **Q-005** UI language? — **Resolved:** English and pt-BR at launch via String Catalog (`Localizable.xcstrings`), following the device language; Info.plist permission strings localized in both (US-13, AC-130–AC-133).
- **Q-006** Over-speed warning? — **Resolved:** No speed warning in v1.
- **Q-007** Keep app copy after save? — **Resolved:** Delete the app's copy after a successful save to Photos (AC-062 stands).
