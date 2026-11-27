# Shadow Protocol — Phase 3D-13 Report
**Stylized Neon Noir, a real shoulder camera, and a joystick that follows your thumb**

Date: 2026-11-27 · Version **0.7.0 / versionCode 9** · Godot 4.7.2.stable
Branch `phase-3d-13` · commits `da4741c` (feature), `a35d3f5` (merge), report commit listed at the end.

## 0. Source access and hygiene

Only `jeyhunmammadov738-ops/shadow-protocol` was modified. The web repository was
not read or cloned this phase; no temporary directory was created, so none
remains. No gameplay logic changed: stealth, AI decisions, weapon specs, mission
state, player health and damage maths are byte-identical to 0.6.1. What changed is
camera geometry, rig geometry/posing, a new cosmetic dressing layer, touch layout
and HUD placement.

## 1. Design decisions

**Camera.** The 3D-8 report claimed an over-the-shoulder view, but the offset was
dead code: `cam.position.x = SHOULDER_OFFSET` ran once in `_ready`, and
`SpringArm3D` rewrites its child's transform every frame. The camera therefore sat
centred and level, which is exactly the "empty dark band in the upper third" the
device run showed. The offset now lives on the arm origin, so the whole rig pivots
from the shoulder and the arm keeps its collision behaviour. Scale note: the player
rig is 90 units tall, so 1 unit is about 2 cm and the owner's "4-5 units" of camera
distance is 200-250 world units; the spring is 230.

The other half of the void was the blocked-camera lift: it triggered at 90%
compression with a -0.95 rad pitch, which fires almost permanently inside 48-unit
corridors and aims at the floor. The lift now triggers under 45% compression and
still climbs steeply enough to clear a 92-unit wall 27 units behind the pivot
(atan(20/27) = 37 degrees, so -0.95 rad is kept for the buried case only).

**Rigs.** The 3D-8 rig was a capsule with pads. It is now a humanoid with a tapered
torso, neck, head, three emissive visor lenses (kept because the 3D-8 suite asserts
the tri-focal language), shoulder masses, elbow and knee pivots, hands, boots, a
jacket layer and a chest strip: 21 meshes and 4 shared materials per rig, so the
draw-call cost stays flat as guards are added.

**Dressing.** A separate layer instead of edits inside the generator: the generator
is covered by BFS reachability tests and should not grow cosmetic branches. Every
repeated element is a MultiMesh batch (seams, floor grid, scuffs, strips, glow
quads, beams), so the measured cost on the legacy layout is 266 meshes in 6
batches, 1 shadowless omni light and distance fog.

**Touch.** Hybrid stick exactly as directed: fixed home base bottom-left, the base
relocates to any press on the left half, and it eases home on release. The right
cluster was rebuilt around the thumb arc with FIRE outermost and larger than
everything else; RLD and MODE are smaller and inboard. No two circles overlap at
1280x720, 2340x1080 or 2400x1080.

## 2. Evidence table (measured this run)

| Gate | Result |
|---|---|
| Phase 3D-13 suite | **89 PASS / 0 FAIL** |
| Camera framing at 3 aspects | horizon ndc_y >= 0.35, corridor point 180 units ahead on screen |
| Pose states | idle/walk/sprint/crouch/downed/hit all reachable; melee impact frame fires once |
| Dressing budget | 266 meshes, 6 batches, 1 real light, within 900/6 caps |
| Hybrid stick | home -> dynamic -> home, vector follows the drag |
| Touch ownership | USE/CROUCH/SPRINT touches never rotate the camera |
| Button overlap | none at 1280x720, 2340x1080, 2400x1080 |
| HUD scale | 1.3 default, clamp 0.9-1.8, panel clear of the stick zone |
| 3D phase-1 | 33 / 0 (camera distance bound now accounts for the shoulder offset) |
| 3D phase-8 | 25 / 0 (tri-focal lenses preserved) |
| Full pipeline | `validate_project.sh` **18 steps, exit 0** |
| Host checks | 169 PASS / 0 FAIL |
| APK | 0.7.0 / 9, 27,013,319 bytes, SHA-256 `c9a9f419…`, cert `74ec3b4e…` |

All other suites unchanged: phase-2 50, phase-3 20, phase-4 32, phase-5 49,
phase-6 38, phase-9 58, phase-10 75, phase-11 46, phase-12 inherited, touch 24,
benchmark 14, 2D smoke 297.

## 3. Real bugs found and fixed

1. **Dead shoulder offset** (3D-8 regression): the camera was never offset; the
   claim in the 3D-8 report was wrong. Fixed at the arm origin.
2. **Camera lift fired constantly**: 90% compression threshold + -0.95 rad pitch
   meant corridors were viewed from directly above. Threshold now 45%.
3. **Phase-1 test hardcoded button offsets**, so it failed on any layout change.
   It now asks the touch layer for live centres, which is what the assertion
   actually means.
4. **Camera distance assertion** ignored the lateral offset; the bound is now the
   arm/offset hypotenuse.
5. **Duplicate dictionary keys** would have broken `mobile_controls.gd` when the
   new cluster was added over the 3D-10 one; caught by the import step.

## 4. Deliberately not done

- Revive/carry for downed guards (unchanged, still open).
- No real-device run this phase, so no FPS or thermal claims. The 79 FPS figure is
  the owner's from 3D-12 and is not re-verified here.
- No PBR, no post-processing stack beyond the existing glow setting: the brief
  ruled it out and the mobile budget is better spent on silhouettes.

## 5. Known limits

- The dressing layer is procedural per layout; a new hand-authored level should
  re-check the mesh budget before shipping.
- The camera is verified analytically, not visually. Subjective framing still needs
  the owner's eyes on a device.
- Corridors narrower than one cell will still compress the arm to a few units; the
  lift keeps the view usable but the player is briefly large in frame.
- Adaptive resolution remains disabled (see 3D-10); it is still the cheapest lever
  if a future device run drops below 60 FPS.

## 6. Device checklist for 0.7.0

1. Does the camera now show corridor ahead instead of a dark band on the top third?
2. Walk a 48-unit corridor and a wide room: does the camera ever end up inside the player?
3. Joystick: press far from the home base, drag, release. Does the base return smoothly?
4. FIRE with a moving thumb: does the thumb ever clip RLD or MODE?
5. Is the weapon panel clear of the stick and readable at arm's length?
6. Guards and the player: do the new limbs read as people at gameplay distance?
7. Five minutes of play: any thermal throttling or frame drops? Report the numbers
   you see; no FPS is claimed in this report.
