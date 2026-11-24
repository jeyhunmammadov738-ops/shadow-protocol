# Shadow Protocol — Phase 3D-8 Completion Report
**3D Visual Quality, TPS Camera Overhaul & Movement Feel**

Date: 2026-11-24 · Commit: 5578c78 · Engine: Godot 4.7.2
Release: 0.3.0 (versionCode 4), package `com.shadowprotocol.game`

## 1. Camera overhaul

- Wall height dropped from 120 to a tactical **92 units**, so corridors read
  as spaces rather than canyons and the arm has room above the sightline.
- **Damped yaw/pitch** (14 / 12 damping factors) replaced the snapping
  rotation, so steering with the left stick is fluid instead of twitchy.
- Spring margin tightened to **4 units**, shoulder offset 26, and the
  blocked-arm case lifts the camera over the wall (`BLOCKED_PITCH`) instead
  of collapsing into the player's head. `is_framing_tight()` exposes the
  state for tests and future HUD hints.
- **Movement FOV**: 68 base widening to 77 while sprinting with 5.0 damping,
  so speed reads without a dolly zoom.

## 2. Procedural tactical character rigs (`scripts/character_rig.gd`)

Zero external assets. Both characters are now articulated multi-part rigs
built from Godot primitives:

- **Player**: torso, tactical vest, shoulder pads, hip-pivoted legs and arms
  with a walking/sprinting stride and torso bob, head, backpack, thigh
  holster and a **glowing tri-focal visor** (three emissive lenses).
- **Guards**: bulkier armour, helmet with a wide emissive visor, shoulder
  pads and a weapon silhouette with a muzzle light. FSM state colours still
  tint the body, so patrol/suspicious/alert stay readable at a glance.

`animate(delta, speed, crouching, sprinting)` drives the stride from real
velocity; crouch sets a braced leg pose.

## 3. Tactical environment and depth

A second, **collision-free detail GridMap** (same MeshLibrary) adds:

- floor **grid seams** on every walkable cell, so movement speed and
  direction are immediately visible on the slate floor;
- wall **baseboards** and **emissive top caps** that give corridors a
  readable edge and a sense of height.

Cost stays inside the mobile budget: **two GridMaps total, 83 mesh
instances**, no real-time shadows, no post-processing.

## 4. Movement feel

Joystick dead zone lowered to **0.12** with a `pow(x, 0.85)` response curve:
small tilts register immediately, large tilts stay linear, and the turn
smoothing is unchanged so the capsule does not overshoot.

## 5. Bug found and fixed

`StealthSystem3D.dynamic_light_at()` iterated `_lights` without checking
validity, so after a layout reload it touched freed light nodes and spammed
"Trying to assign invalid previously freed instance". Guarded and verified:
the phase-8 restart cycle now reports zero such errors.

## 6. Verification

| Gate | Result |
|---|---|
| 3D phase-8 (new: visuals, camera, feel) | **25/25** |
| 3D touch regression | 24/24 |
| 3D phase-6 / 5 / 4 / 3 / 2 / 1 | 38/38, 49/49, 32/32, 20/20, 50/50, 33/33 |
| 2D smoke (prototype intact) | 297/297 |
| 3D benchmark | 14/14 |
| Android host checks | 123/123 |
| validate_project.sh (14 steps) | exit 0 |

## 7. Release artifact

`ShadowProtocol-v0.3.0-release.apk` (26.6 MB): v2+v3 signatures verified,
certificate `74ec3b4ec475f65517f0676b30d801f9fc557a5bb733dcabd70a5f016c574a0b`,
debug certificate absent, `arm64-v8a` only, versionName 0.3.0 /
versionCode 4.

APK SHA-256: `a5472c2e1df22b9f553a8ef3db22d1efd406d9d538cffc5daefa152808cf3432`

## 8. What to check on the POCO X5 Pro 5G

1. Corridors read as rooms; the camera no longer fills the screen with the
   back of the head near walls.
2. Steering feels immediate; sprint visibly widens the view.
3. Player visor and guard helmets/visors are visible and the guards' state
   colour still reads at distance.
4. Floor seams make speed and direction obvious.
5. FPS stays at or above 60 in alert-stress moments.

## 9. Known limits

- Rig animation is procedural rotation only (no skeletal animation, no IK).
- Wall trim is a second GridMap layer, not per-face bevel geometry.
- No real-time shadows by design (mobile budget); depth comes from emissive
  trim and the palette contrast.
- Headless metrics remain CPU-side; device GPU numbers still come from the
  D-series checklist.
