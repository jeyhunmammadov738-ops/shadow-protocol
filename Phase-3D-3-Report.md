# Shadow Protocol — Phase 3D-3 Completion Report
**StealthSystem 3D Port with Exact 2D/3D Mathematical Parity**
Date: 2026-11-23 · Commit: 417ac6f · Build: Godot 4.7.2, mobile renderer

## 1. Scope delivered

Phase 3D-3 ports the stealth and noise core to 3D while leaving the 2D
prototype completely intact. The 2D autoload (`StealthSystem`), the 2D
light classes and every 2D scene/script are unmodified; the 3D core is a
separate class owned by `main3d.tscn`.

New files:

| File | Role |
|---|---|
| `scripts/stealth_system_3d.gd` | 3D stealth/noise core: Vector3 world coordinates, `(x, z)` grid mapping, identical constants and operation order |
| `scripts/light_source_3d.gd` | 3D dynamic light with the same quadratic falloff model; optional visual `OmniLight3D` (never authoritative) |
| `scripts/moving_light_3d.gd` | Ping-pong moving light on the XZ plane, same deterministic triangle-wave timing |
| `scripts/noise_event_3d.gd` | Noise event contract carrying a Vector3 origin |

Modified (3D only): `scripts/player3d.gd` (live visibility + noise
publishing), `scripts/main3d.gd` (owns the core, configures it from the
generated level, spawns and registers lamps), `tools/validate_project.sh`,
`tools/test_build_android_host.sh`, `roadmap.md` (dated note).

## 2. Preserved formulas (no drift)

| Element | Value (2D and 3D) |
|---|---|
| Shadow / lit cell illumination | 0.25 / 1.0 |
| Crouch multiplier | 0.55 |
| Motion visibility boost | 0.15, applied once after posture, then clamped |
| Dynamic light | quadratic falloff `intensity * (1 - d/r)^2`, zero beyond radius, additive clamp at 1.0 |
| Layer combination | `max(grid, dynamic)` - no double counting |
| Noise radii | crouch 90, walk `220 * (0.55 + 0.45 * speed_ratio)`, sprint 320 |
| Noise cadence / dedup | 0.25 s, one event per source per frame |

## 3. Parity evidence (tolerance 1e-6)

`tools/test_3d_phase3.gd` compares against the **real** 2D
implementation (the live autoload and `scripts/light_source.gd`), feeding
identical logical inputs with `2D (x, y) <-> 3D (x, 0, y)`:

| Comparison | Samples | Result |
|---|---|---|
| Grid illumination | 64 cells | PASS |
| Quadratic light falloff | 289 sample points | PASS |
| Visibility (illumination x crouch x speed) | 1210 combinations | PASS |
| Noise radius (crouch/sprint/speed) | 28 combinations | PASS |
| Moving-light path | 7 elapsed times | PASS |
| World <-> grid conversion | 5 cases both directions | PASS |
| Same-frame noise dedup | 1 event each | PASS |

**Measured maximum numeric delta: 0.0** (tolerance 1e-6).

## 4. Live integration

- `Player3D` is wired to the 3D core and pushes visibility every physics
  frame (value stays inside 0..1; lit cells read 1.00 vs 0.25 in shadow).
- Movement publishes noise events through
  `StealthSystem3D.publish_noise()`: walking lands in the 220-unit band,
  crouched events are exactly 90, sprint events exactly 320, matching the
  2D player's cadence.
- `main3d` configures the core from the generated GridMap level
  (`lit_cells`, `wall_cells`, cell size 48, origin) and registers every
  layout lamp (static and moving) with it. Gameplay geometry stays on the
  XZ plane so the parity proof applies; the visual lamp sits slightly
  above the floor and is never authoritative.

## 5. Validation gate (all fresh)

| Gate | Result |
|---|---|
| Headless import | exit 0 |
| 2D boot (main.tscn, 180 frames) | exit 0 |
| 2D smoke test | **297 / 297 PASS** (unbroken) |
| 3D phase-1 (player, camera, touch zones) | 33 / 33 PASS |
| 3D phase-2 (GridMap parity, collisions) | 50 / 50 PASS |
| 3D phase-3 (parity + integration) | **20 / 20 PASS**, max delta 0.0 |
| Android host checks | 64 / 64 PASS (was 50) |
| `validate_project.sh` | exit 0, 8-step pipeline |

Release APK rebuilt with the 3D content and verified: package
`com.shadowprotocol.game` 0.1.0 (1), arm64-v8a, apksigner v2+v3, release
certificate unchanged (`74ec3b4e...`), debug certificate absent.
APK SHA-256: `b95aa92649590316468212462ea219d284db7c748aabda84786ab76864da2faf`.

## 6. Repository state

- Commit `417ac6f` — code, tests, host checks, roadmap note (15 files).
- Report commit follows this document.
- Roadmap verification: 8 phase headers, 30 tasks, 30/30 complete, unique
  IDs, focus line intact, three dated 3D programme notes, no ninth phase.
- APK and build artifacts remain outside the repository.

## 7. Known limitations

- The 3D stealth model inherits the 2D approximations: lights have no wall
  occlusion, and illumination is a deterministic gameplay model rather
  than a shadow simulation.
- `is_cell_blocked()` in the 3D core implements the wall/door query, but
  no 3D door nodes exist yet (Phase 3D-5).
- Visual lamp height differs from gameplay height by design and is
  documented; gameplay queries use the XZ plane.

## 8. Stop gate

Phase 3D-3 is complete and committed. Work pauses here pending approval
before Phase 3D-4.
