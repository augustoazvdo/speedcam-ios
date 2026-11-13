# SpeedCam — Tasks

Spec: [spec.md](spec.md) · Design: [design.md](design.md). Status: Approved.

Rules: tests first (R-01). Each task lists Story · ACs. Mark `[x]` when the test passes. All questions are resolved (spec §5); no task is blocked. If a new `Q-xxx` is raised, tasks touching it are blocked until answered.

## Phase 0 — Scaffold
- [ ] T-001 Create `project.yml` (app, unit, UI test targets; Debug/Release; iOS 17; bundle id `com.augusto.speedcam`; Info.plist usage strings; no background modes; localizations `en`, `pt-BR`; git-ignored `Local.xcconfig` for team). Generate with xcodegen; build empty app on "iPhone 18 Pro". · US-11 · AC-101, AC-104
- [ ] T-002 `.gitignore` (xcodeproj optional, DerivedData, `Local.xcconfig`, `*.mobileprovision`, `*.p12`, exports). · US-11 · AC-104
- [ ] T-003 `scripts/check-traceability.sh`: parse AC ids in spec.md, grep tests for AC refs, fail on missing/unknown. · all · (audit tooling)
- [ ] T-004 `scripts/extract-frame.sh` (ffmpeg, fallback AVAssetImageGenerator Swift script). · US-10 · AC-093
- [ ] T-005 Protocols + `AppEnvironment` + `LaunchArguments` (DEBUG) skeletons: `FrameSource`, `LocationProvider`, `PhotoLibrarySaving`, `PermissionsProviding`, `StorageMonitoring`, `ThermalMonitoring`, `Clock`. · US-10 · AC-090, AC-091, AC-103
- [ ] T-006 Add `Localizable.xcstrings` and `InfoPlist.xcstrings` (en + pt-BR) with the four usage strings; wire into `project.yml`. · US-13 · AC-131

## Phase 1 — Speed logic (unit tests first)
- [ ] T-010 Tests: `SpeedSmoother` invalid −1 → "--"; stale > 3 s → "--"/noFix; poor accuracy → "--"/weak; < 2 km/h → "0"; smoothing bound; rounding; 13.89 m/s → 50 km/h / 31 mph. · US-05, US-09 · AC-040–AC-045
- [ ] T-011 Implement `SpeedSmoother` + `SpeedReading`. · US-05 · AC-040–AC-045
- [ ] T-012 Tests: `SettingsStore` default km/h, persists mph across instances. · US-09 · AC-080, AC-081
- [ ] T-013 Implement `SettingsStore`. · US-09 · AC-080, AC-081
- [ ] T-016 Tests: `SettingsStore.overlayCorner` default bottom-left, persists across instances. · US-12 · AC-120, AC-123
- [ ] T-017 Implement `overlayCorner` in `SettingsStore`. · US-12 · AC-120, AC-123
- [ ] T-014 Tests: `SimulatedLocationProvider` scenarios deterministic. · US-10 · AC-091
- [ ] T-015 Implement `SimulatedLocationProvider` (DEBUG) and `CoreLocationProvider` (When In Use, foreground only). · US-05, US-10, US-11 · AC-091, AC-092, AC-102

## Phase 2 — Overlay
- [ ] T-020 Tests: `OverlayRenderer` renders into a known pixel buffer; overlay region has non-background pixels; "--" state; mph/km/h labels; each orientation places overlay upright in the expected corner; timestamp format. · US-04, US-06 · AC-030, AC-034, AC-050
- [ ] T-021 Implement `OverlayModel` + `OverlayRenderer` (cached CIImage, Metal CIContext). · US-04 · AC-030, AC-034, AC-050
- [ ] T-022 Tests: renderer places overlay in each of the 4 corners for portrait, landscape-left, landscape-right (12 cases, pixel-region asserts); pt-BR date format. · US-12, US-13 · AC-122, AC-133
- [ ] T-023 Implement corner + locale support in `OverlayRenderer`. · US-12, US-13 · AC-122, AC-133

## Phase 3 — Recording pipeline
- [ ] T-030 Tests: `RecordingCoordinator` state machine (start/stop, debounce, every stop reason finalizes, storage start threshold, thermal serious warn / critical stop, interruption, background, camera revoke stop, location revoke continue). Fakes for all monitors. · US-03, US-08 · AC-020, AC-021, AC-023, AC-070–AC-076, AC-078
- [ ] T-031 Implement `RecordingCoordinator`, `StorageMonitor`, `ThermalMonitor`, `InterruptionMonitor`. · US-03, US-08 · same
- [ ] T-032 Tests: `RecordingWriter` with `SyntheticFrameSource` + silent audio writes a playable .mov: video track 1080p ~30 fps, audio track present when enabled, A/V offset ≤ 100 ms, orientation transform, overlay on frames; mid-recording finish produces playable file. · US-04, US-06, US-08 · AC-031, AC-032, AC-052, AC-072, AC-073
- [ ] T-033 Implement `SyntheticFrameSource` (DEBUG) and `RecordingWriter` (fragment interval). · US-04, US-10 · AC-031, AC-032, AC-090
- [ ] T-034 Implement `CameraFrameSource`, `AudioSource`, `CaptureSessionService` (sessionQueue, interruptions). Device-only manual check. · US-02, US-04 · AC-010, AC-031
- [ ] T-035 Tests: `ClipRecovery` recovers playable partial file on launch / reports unrecoverable. · US-08 · AC-077
- [ ] T-036 Implement `ClipStore` + `ClipRecovery`. · US-08 · AC-077

## Phase 4 — Save & permissions
- [ ] T-040 Tests: `PhotoLibrarySaver` flow with fake: success → toast + temp deleted; denied → kept pending, retried on activation. · US-07, US-01 · AC-006, AC-060, AC-062
- [ ] T-041 Implement `PhotoLibrarySaver` (`.addOnly`) + pending queue. · US-07 · AC-006, AC-060, AC-062 (thumbnail JPEG generated before deleting the sandbox copy, ASM-012)
- [ ] T-042 Tests: `PermissionsService` + view model: onboarding before prompts, request order, no Always/full access, denied states per permission, refresh on becoming active. · US-01 · AC-001–AC-007
- [ ] T-043 Implement `PermissionsService` (openSettings deep link). · US-01 · AC-001–AC-007

## Phase 5 — UI
- [ ] T-050 UI tests (launch args: synthetic camera, simulated location, skip onboarding): idle screen controls + "No clips yet"; tap record → red dot + timer; stop → "Saving…" → "✓ Saved to Photos"; thumbnail opens clip; unit toggle live; denied/no-GPS states each show one action. · US-02, US-03, US-07, US-09 · AC-011, AC-012, AC-020, AC-021, AC-061, AC-082, AC-110–AC-113
- [ ] T-051 Implement `CameraViewModel`, `CameraScreen`, `PreviewView`, `ControlsView`, `StatusViews`, `Toast`, `OnboardingView`, haptics. · US-01–US-03, US-07, US-09 · same
- [ ] T-052 UI test: idle timer disabled while recording, restored after (via exposed debug state). · US-03 · AC-022
- [ ] T-053 Implement `IdleTimerController`. · US-03 · AC-022
- [ ] T-054 UI tests in portrait + landscape left/right: controls same order/style, no mid-clip rotation of file. · US-06 · AC-051, AC-052, AC-112
- [ ] T-055 Implement orientation handling (UI rotation, lock at record start). · US-06 · AC-050–AC-052
- [ ] T-056 UI tests: settings sheet corner picker moves preview overlay + haptic; persists after relaunch; disabled with hint while recording. · US-12 · AC-121, AC-123, AC-124
- [ ] T-057 Implement corner picker in settings sheet. · US-12 · AC-121, AC-124
- [ ] T-058 UI tests with `-AppleLanguages (pt-BR)` and `(en)` (and `(fr)` fallback): key screens, toasts, errors show expected language. · US-13 · AC-130
- [ ] T-059 Localize all UI strings via `Localizable.xcstrings`. · US-13 · AC-130, AC-132

## Phase 6 — End-to-end on Simulator
- [ ] T-060 UI/E2E test: launch with `-SpeedCamAutoRecordSeconds 5 -SpeedCamExportPath … -SpeedCamSyntheticCamera YES -SpeedCamSimulatedLocation constant50kmh`; assert export file exists, extract frame at 2 s, assert overlay pixels; save PNG as test attachment. · US-10 · AC-093, AC-094, AC-030
- [ ] T-061 Implement `AutoRecordRunner` + export (DEBUG). · US-10 · AC-093
- [ ] T-062 Manual check script: `xcrun simctl location "iPhone 18 Pro" start --speed=14 <waypoints>` with CoreLocation provider → overlay ≈ 50 km/h in extracted frame. · US-10 · AC-092
- [ ] T-063 Device check (physical iPhone): 10-min recording, dropped frames ≤ 1%, overlay on every sampled frame, preview latency ≤ 1.5 s. · US-02, US-04 · AC-010, AC-033

## Phase 7 — Privacy & release checks
- [ ] T-070 Test/script: Release build — DEBUG symbols (`SyntheticFrameSource`, `SimulatedLocationProvider`, `AutoRecordRunner`) absent (`nm`/`strings`), launch args ignored. · US-11 · AC-103
- [ ] T-071 Test/script: no `URLSession`/`Network` usage in sources, no third-party packages, built Info.plist keys present and no Always/background location. · US-11 · AC-100, AC-101, AC-102, AC-105
- [ ] T-072 Secret scan of repo (`git grep -nE` for keys/tokens/p12/mobileprovision). · US-11 · AC-104
- [ ] T-073 Script: validate both catalogs — every key has `en` and `pt-BR` values, none stale/missing; grep sources for hard-coded user-facing literals; check built app has `pt-BR.lproj/InfoPlist.strings` with the 4 keys. · US-13 · AC-131, AC-132
- [ ] T-074 Manual check: launch in pt-BR on a fresh simulator, confirm each permission prompt text is Portuguese (screenshot). · US-13 · AC-131

## Phase 8 — Audit
- [ ] T-080 Audit: run `scripts/check-traceability.sh` — every AC-001…AC-133 maps to ≥ 1 automated test or a documented device/manual check (AC-010, AC-033, AC-092, AC-131 prompt screenshots), every test references a valid AC, all tasks done, no open Q-xxx; list remaining ASM-xxx in the report. · all · all
