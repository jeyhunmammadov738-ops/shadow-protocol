# Shadow Protocol — Phase 3D-4 Completion Report
**Enemy AI in 3D + Vision Cone**

Date: 2026-11-23 · Commit: 0446b1f · Engine: Godot 4.7.2 (mobile renderer)

## 1. Scope delivered

| Requirement | Status |
|---|---|
| `scenes/enemy3d.tscn`, `scripts/enemy3d.gd`, `scripts/vision_cone_mesh.gd` | Delivered |
| Six-state FSM preserved (PATROL, SUSPICIOUS, INVESTIGATING, ALERT, SEARCHING, RETURNING) | Verified |
| `ai_interval` decision throttling | Verified (40 ticks / 240 frames) |
| Suspicion thresholds and rates unchanged | 0.3 / 1.0, gain 1.6, decay 0.45 |
| 3D vision cone: 100° FOV, 340 range, Vector3 dot gate | Verified |
| 3D raycast LOS on wall layer 1 (`PhysicsRayQueryParameters3D`) | Verified |
| Decorative cone only (zero gameplay authority) | Verified |
| Noise rules: ALERT ignores, duplicate < 24, margin +40, clean unsubscribe | Verified |
| Guards from layout '5' markers, deterministic BFS + LOS patrol | Verified |
| `tools/test_3d_phase4.gd` wired into `validate_project.sh` | Verified |
| 8-enemy stress / frame budget | 0.003 ms per AI decision; 240-frame loop 4.0 s |

## 2. Design notes

`enemy3d.gd` is a line-by-line port of `enemy.gd`. Only the spatial layer
changed: `Vector3` facing, XZ planar distance for the gameplay model (guards
and player share one floor) and a real 3D raycast from guard eye (60) to
player chest (45). The detection formula is untouched:

```
strength = player.visibility * (1 - 0.5 * clamp(dist / range, 0, 1))
close range floor inside range * 0.25
```

The visual cone (`vision_cone_mesh.gd`) is a procedural triangle fan in the
XZ plane at eye height, tinted from the real FSM state. It performs no
detection and is never read by gameplay code.

Patrol routes are generated in `main3d.gd`: BFS over open XZ cells (4 steps),
then up to four farthest-first waypoints filtered by grid line of sight. No
randomness and no physics queries, so routes are reproducible (asserted by
building the same route twice in the test).

## 3. Verification (fresh run)

| Gate | Result |
|---|---|
| Headless import | exit 0 |
| 2D boot (180 frames) | exit 0 |
| 2D smoke | 297 / 297 |
| 3D phase-1 (player, camera, touch) | 33 / 33 |
| 3D phase-2 (GridMap parity) | 50 / 50 |
| 3D phase-3 (stealth parity, delta 0.0) | 20 / 20 |
| 3D phase-4 (enemy AI) | 32 / 32 |
| Android host checks | 74 / 74 |
| `validate_project.sh` | exit 0 |

Release APK rebuilt and re-verified (v2+v3, certificate
`74ec3b4e…` unchanged, SHA-256 `04999fde…`).

## 4. Known limitations

- Vision and noise models remain the documented non-occluded gameplay
  approximations (same as 2D); only enemy line of sight uses physical rays.
- Guards have no door interaction yet (Phase 3D-5 scope).
- Enemy-enemy collisions are enabled; crowds can jostle on narrow paths.
- Frame-budget figures are headless CPU measurements, not device GPU
  measurements; on-device performance still needs a physical test pass.

## 5. Next phase (awaiting approval)

Phase 3D-5: 3D mission objects (terminals, doors, extraction beacon) wired to
the interaction pipeline.
