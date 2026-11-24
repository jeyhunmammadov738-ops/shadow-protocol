# Shadow Protocol — Phase 3D-7 Completion Report
**Performance + Android Export + Device Acceptance (final 3D stage)**

Date: 2026-11-24 · Commit: 9d76f5e · Engine: Godot 4.7.2 (mobile renderer)
Release: 0.2.0 (versionCode 2), package `com.shadowprotocol.game`

## 1. What shipped

The Android build now boots the 3D game. `project.godot` points
`run/main_scene` at `res://scenes/main3d.tscn` and declares
`config/version="0.2.0"`; `export_presets.cfg` carries `versionCode 2`,
`versionName 0.2.0`, `arm64-v8a` only, and the unchanged package and
release signing identity. The 2D prototype remains in the repository and
still passes its 297/297 smoke suite, so both builds stay testable.

## 2. Benchmark results (headless, host CPU)

`tools/benchmark_3d.gd` runs five scenarios against the real
`main3d.tscn` and gates 15 checks:

| Scenario | Wall time / 180 frames | Fixed-step floor | Result |
|---|---|---|---|
| steady state | 3001 ms | 3000 ms | no stalls |
| active movement | 3002 ms | 3000 ms | no stalls |
| alert stress (all guards chasing) | 3002 ms | 3000 ms | no stalls |
| interactions (terminal + door) | 3001 ms | 3000 ms | no stalls |
| restart cycles (4 layouts) | 3001 ms | 3000 ms | no stalls |

Structural and leak evidence after the restart cycles: 1 GridMap for the
whole level, 28 mesh instances, 1776 objects, 100 nodes, 38.6 MB static
memory, zero duplicated mission signal connections, guard and terminal
counts matching the active layout.

**Honest limitation:** the headless renderer is a dummy. Draw-call counts
and FPS are not available here and are never reported as device
performance. This harness proves the simulation keeps up with the fixed
60 Hz step and that nothing leaks; the GPU numbers come from the device
checklist.

## 3. Signed release verification

`tools/build_android.sh` (environment-variable signing flow) produced
`ShadowProtocol-v0.2.0-release.apk` (26.6 MB).
`tools/verify_release_apk_host.sh` reports:

- package/version: `com.shadowprotocol.game` 0.2.0 / versionCode 2, `arm64-v8a`
- signature verifies (v2 + v3)
- release certificate fingerprint `74ec3b4ec475f65517f0676b30d801f9fc557a5bb733dcabd70a5f016c574a0b`
- debug certificate absent

APK SHA-256: `4f7571a9b7b836c26444de92515d78f457ba52d3f86873fa389c36149cf4bb37`

## 4. Validation gate (all green)

`tools/validate_project.sh`, 12 steps, exit 0: import, boot of the new 3D
default scene, 2D smoke 297/297, 3D phase-1 33/33, phase-2 50/50, phase-3
20/20, phase-4 32/32, phase-5 49/49, phase-6 38/38, 3D benchmark 15/15,
Android host checks 109/109.

## 5. Device acceptance (yours to run)

`docs/ANDROID_DEVICE_ACCEPTANCE.md` now carries a dedicated 3D section with
18 checks (D1..D18) for the POCO X5 Pro 5G on Android 14: cold start,
steady/moving/alert FPS, joystick and camera ergonomics, button
responsiveness, HUD legibility, interaction prompts, door/terminal/
extraction loop, restricted-zone detection pressure, enemy LOS, audio and
haptics, thermal stability, five restart cycles with meminfo, and
background/foreground. Performance failures (D2/D3/D4/D16) and functional
failures (D10/D11/D12/D17) are treated as blockers.

## 6. Roadmap status

The 30-task acceptance roadmap is unchanged and complete (8 phases, 30/30,
no phase 9). The 3D conversion programme now has seven delivered phases,
each with a dated note in `roadmap.md`.

## 7. Known limits

- Headless metrics are CPU-side only; device GPU/jank numbers require D2/D3/D4/D16.
- 3D lights still use the documented no-occlusion model shared with 2D.
- Doors slide rather than swing, and patrol routes do not path through doors.
- The 2D prototype is no longer the default scene; it stays available for regression.
