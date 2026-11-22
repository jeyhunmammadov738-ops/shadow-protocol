# Shadow Protocol — Phase 3D-1 Completion Report (3D Skeleton + Player + TPS Camera)

**Date:** 2026-11-22
**Scope:** Approved Phase 3D-1 of the 2D→3D conversion programme.
**Result:** COMPLETE — 3D phase-1 acceptance test 33/33 PASS, 2D prototype unchanged (smoke 297/297), host checks 40/40, release APK rebuilt and signature-verified.

---

## A. Deliverables (new files only — 2D scenes untouched)

| File | Purpose |
|---|---|
| `scenes/main3d.tscn` | 3D test arena: ground, three collision walls, sun, world environment, player instance, shared touch layer, HUD |
| `scenes/player3d.tscn` | CharacterBody3D + capsule collider + procedural capsule/visor meshes + CameraRig/SpringArm3D/Camera3D |
| `scripts/player3d.gd` | Camera-relative movement, 2D-identical speed constants, crouch/sprint posture, grounding |
| `scripts/camera_rig.gd` | Yaw/pitch TPS rig, pitch clamping, SpringArm3D collision, touch-ownership filtering |
| `scripts/main3d.gd` | Scene wiring: shared touch layer → 3D player; debug HUD |
| `tools/test_3d_phase1.gd` | Headless acceptance test (33 checks) |

Modified (minimal, justified):

| File | Change |
|---|---|
| `scripts/mobile_controls.gd` | **Additive** `is_position_owned(pos)` — single source of truth for button/joystick ownership. No existing behaviour or call site changed. |
| `tools/validate_project.sh` | Added step [5/6]: 3D phase-1 test gate (renumbered steps). |
| `tools/test_build_android_host.sh` | +14 static checks (3D files present, 3D types, touch-ownership wiring, 2D main scene intact). 26 → 40 checks. |
| `roadmap.md` | Dated 3D programme note. Task counts unchanged (8 phases, 30/30). |

The 2D scenes `main.tscn`, `player.tscn`, `enemy.tscn` were **not** modified; their content is verified unchanged by host checks and by the 297-check smoke suite.

## B. Touch conflict rule (requirement 2)

One source of truth: `mobile_controls.gd::is_position_owned()` returns true for the joystick zone (left 45%) and for any touch inside the SPRINT/CROUCH/USE hit circles. `camera_rig.gd::accepts_touch()` refuses those touches, so:

- a press on SPRINT/CROUCH/USE can never start a camera drag (verified by test: dragging on the USE button leaves yaw unchanged);
- the joystick finger never rotates the camera;
- any other right-side touch rotates the camera (verified: drag rotates yaw).

When no touch overlay is visible (desktop), right-mouse drag rotates the camera.

## C. Movement parity with the 2D prototype

Same constants as `scripts/player.gd`: walk 240, crouch 105, sprint ×1.45, acceleration 12, friction 10 (unit scale 1 unit = 1 cm → 2.4 / 1.05 / 3.48 m/s). Movement is projected onto the camera yaw basis; the body faces the movement direction; crouch shrinks the capsule (90 → 58) and lowers the camera pivot (62 → 42).

## D. Camera

SpringArm3D at 150 units with 8-unit margin, world layer 1, player body excluded. Pitch clamps at −60°/+26°. Camera verified behind and above the player at yaw 0.

## E. Fresh verification results (all on the final tree)

| Check | Command | Result |
|---|---|---|
| Resource import | `godot --headless --path . --import` | exit 0 |
| Headless boot (2D main scene, 180 frames) | `godot --headless --path . --quit-after 180` | exit 0 |
| 2D smoke suite | `res://tools/smoke_test.tscn` | 297/297 PASS |
| 3D phase-1 acceptance | `--script res://tools/test_3d_phase1.gd` | 33/33 PASS |
| Full validation (import + boot + smoke + 3D + host) | `tools/validate_project.sh` | exit 0 |
| Host build/signing checks | `tools/test_build_android_host.sh` | 40/40 PASS |
| Release APK build | `tools/build_android.sh` (env signing) | exit 0, apksigner OK |
| APK verification | `tools/verify_release_apk_host.sh` | 5/5 PASS |

Release APK: 26,740,246 bytes, package `com.shadowprotocol.game` 0.1.0 (1), arm64-v8a, signature v2+v3, certificate `74ec3b4e…` unchanged (same signing identity), 165 entries including the packed 3D scenes. APK SHA-256: `20a2f188150f9b0b0b7182fdcd6e9c232a1ffa988b262cea99cb47f0b109697a`.

Note: `build_android.sh` prints a harmless "Could not create child process: …/adb" line — the export template probes ADB after building; no device/ADB is used, and the build exits 0.

## F. Roadmap verification (mandatory pass)

- Checkboxes: 30/30 complete, zero open.
- Phases: 8 (no ninth phase added); 30 unique task IDs preserved.
- Evidence: P7-T2/P8-T1/P8-T3 device evidence intact from 2026-11-22.
- Counts: 8/8 phases, 30/30 tasks — unchanged by 3D work.
- Focus line: "FINAL ACCEPTANCE CLOSED (2026-11-22)" — still accurate; the new dated note records the 3D programme as separate from the acceptance roadmap.

## G. Limits and known gaps (Phase 3D-1 scope)

- No 3D level generation yet (Phase 3D-2): the arena is a fixed blockout.
- No stealth/AI in 3D yet: `StealthSystem` and enemy FSM remain 2D (Phase 3D-3/3D-4).
- No 3D audio, no interactable objects (Phase 3D-5).
- Camera has no auto-recenter or shoulder offset yet.
- Headless test covers logic and wiring only; on-device feel (camera sensitivity, thumb ergonomics) needs a device pass at the end of the 3D programme.
- 3D scene is not reachable from the shipped app's main scene (2D prototype remains the default) — intentional for parallel development.

## H. Git

Commit includes the 3D files, the three tool changes, the roadmap note and this report. APK/ZIP are excluded from the repository per standing instruction. Push verified against the canonical repo `jeyhunmammadov738-ops/shadow-protocol`.

## I. Next step

Phase 3D-2 (GridMap level generation from `level_catalog` layouts, 48-unit cells) awaits owner approval.
