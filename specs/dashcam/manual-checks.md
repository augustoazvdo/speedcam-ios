# Manual and device checks

- **AC-010, AC-033 — physical iPhone, pending (T-063):** record for 10 minutes; inspect sampled frames for the overlay, measure dropped-frame rate and preview latency. No physical iPhone was available in this environment.
- **AC-092 — Simulator route check, failed (T-062):** `scripts/check-sim-location.sh` granted When In Use, ran `simctl location start --speed=14`, recorded and extracted a frame. The frame showed `-- km/h` and `GPS weak`; iOS 27.2 supplied invalid speed accuracy, as recorded in ASM-018. A separate `Freeway Drive` run showed a valid 11 km/h, not a controllable 50 km/h.
- **AC-131 — pt-BR permission prompts, pending (T-074):** capture camera, microphone, location When In Use and Photos add-only system prompts on a fresh simulator set to pt-BR. Bundle strings are covered by `LocalizationBundleTests`; screenshots are still required.
