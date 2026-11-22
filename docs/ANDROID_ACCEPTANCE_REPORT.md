# Shadow Protocol — Final Android Acceptance Report

**Date:** 2026-11-22
**Scope:** Final acceptance review of the three device-dependent roadmap tasks (P7-T2, P8-T1, P8-T3). No source, rendering or signing changes were made.

---

## 1. Device and Android version

| Item | Value |
|---|---|
| Device | POCO X5 Pro (Snapdragon 778G+, 6/7-series mid-range class) |
| Android version | Android 14 |
| Display refresh rate | 120 Hz (display rate, not game FPS) |

## 2. Release artifact identity

| Item | Value |
|---|---|
| Package | `com.shadowprotocol.game` |
| Version | 0.1.0 (versionCode 1) |
| Build | Signed release APK, built 2026-10-24 |
| APK SHA-256 | `aba40fe03ad8abad704518206e3be1afe4f51d0eabec98d2086c8c4dc7c18905` |
| Release certificate SHA-256 | `74ec3b4ec475f65517f0676b30d801f9fc557a5bb733dcabd70a5f016c574a0b` |
| Signature schemes | APK Signature Scheme v2 + v3 (debug certificate absent) |

This is the same artifact previously published as the GitHub pre-release `v0.1.0-android-test.1`. It was not rebuilt or re-signed for this acceptance pass.

## 3. Physical-device functional test results (owner-reported, 15/15 PASS)

First-hand owner observations on the physical device, not independently automated tests.

Initial 7/7:

| # | Check | Result |
|---|---|---|
| 1 | APK installation succeeded | PASS |
| 2 | Game launches and renders correctly | PASS |
| 3 | Touchscreen joystick controls | PASS |
| 4 | Running and crouching | PASS |
| 5 | Enemies react to the player | PASS |
| 6 | Missions can be completed | PASS |
| 7 | Gameplay restarts without crashing | PASS |

Advanced 8/8:

| # | Check | Result |
|---|---|---|
| 1 | Multitouch controls | PASS |
| 2 | Enemy detection | PASS |
| 3 | Sound and stealth mechanics | PASS |
| 4 | Mission failure behavior | PASS |
| 5 | Gameplay interactions | PASS |
| 6 | Background/resume behavior | PASS |
| 7 | HUD behavior | PASS |
| 8 | Fifteen-minute extended gameplay | PASS |

## 4. SurfaceFlinger measurement source

`shadow_protocol_timestats.txt` (SurfaceFlinger TimeStats), single recording supplied by the owner; the only performance measurement used for this review.

- `statsStart = 1795365678`, `statsEnd = 1795367015`
- Game layer: `SurfaceView[com.shadowprotocol.game/com.godot.game.GodotAppLauncher](BLAST)`

## 5. Recording duration

1337 seconds (22 min 17 s). This is the SurfaceFlinger recording window; it does not by itself prove 22 min 17 s of continuous active gameplay. A separate 15-minute continuous gameplay run was reported by the owner.

## 6. Measured game-layer average FPS

**59.869 FPS** over 76,989 game-layer frames, with `droppedFrames = 0`, `lateAcquireFrames = 0`, `badDesiredPresentFrames = 0` reported at the layer level. These layer counters must not be read as proof of perfect frame pacing.

## 7. Frame-interval estimates (histogram bins)

| Percentile | Estimate |
|---|---|
| P50 | ~16 ms |
| P90 | ~16 ms |
| P95 | ~25 ms |
| P99 | ~25 ms |

Derived from the game-layer present-to-present histogram (16 ms bin = 70,761 frames, 91.9%; 25 ms bin = 5,958 frames). These are bin estimates, not exact per-frame measurements.

## 8. Long-frame-interval percentage

Intervals of 24 ms or longer: **6,089 frames = 7.91%** of 76,989.

## 9. Frame-pacing and jank interpretation (limits)

- The game layer reports `totalTimelineFrames = 0`, so no reliable game-specific FrameTimeline jank percentage can be derived.
- Global statistics (`totalFrames = 77685`, `missedFrames = 413`) aggregate other Android UI layers and are not attributable to Shadow Protocol.
- Not every frame met the ideal 16.67 ms interval (7.91% were 24 ms or longer); the average remains within ~0.2% of 60 FPS.
- Thermal evidence is qualitative: the owner reported normal heating and no observed degradation.

## 10. Final acceptance decisions

| Task | Decision | Basis |
|---|---|---|
| **P7-T2** — Stable 60 FPS on mid-range hardware | **COMPLETE** | 59.869 FPS average over a 22m17s instrumented window on mid-range hardware, 91.9% of frames at 16 ms, zero layer-level dropped frames, 15-min sustained run, owner-reported smoothness and normal thermals. Roadmap target is a practical stable-60 target, not an exact 60.000 requirement. |
| **P8-T1** — End-to-end Android installation | **COMPLETE** | Host chain verified earlier (setup preflight, signed debug/release builds); installation now confirmed on a physical device: the signed release APK installed, launched and ran stably. Deviation: manual side-load on Windows 11 instead of the ADB-based `install_android.sh` path (ADB out of protocol). |
| **P8-T3** — On-device gameplay verification | **COMPLETE** | 15/15 owner-executed functional checks PASS, covering touch/multitouch controls, movement, detection, stealth/audio, mission success and failure, interactions, background/resume, HUD and a 15-minute extended session. |

## 11. Outstanding limitations and follow-up recommendations

- No per-scenario benchmark breakdown (A_legacy_steady … I_door_active) was captured on-device; the evidence is a single aggregate window. If scenario-level regression tracking is wanted later, run the existing benchmark scenarios on-device and record them separately.
- No reliable FrameTimeline jank percentage exists for this build (layer timeline counter is zero); future performance work could enable FrameTimeline-based measurement.
- Thermal behavior is owner-reported only; no instrumented thermal trace.
- The ADB-based `install_android.sh` path remains unexercised; it can be validated whenever a wired-device workflow is available.
- Signing backup: single owner-held copy (public encrypted archive + separately delivered password); no independently verified second offsite copy.
- No further physical-device testing is required for the current acceptance criteria.

---

**Final roadmap state: 30 / 30 tasks (100%).**
Shadow Protocol roadmap acceptance is COMPLETE: 30/30 tasks.
