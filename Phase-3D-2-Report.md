# Shadow Protocol — Phase 3D-2 Report: GridMap Level Generation

**Date:** 2026-11-23
**Scope:** Phase 3D-2 only. 2D prototype untouched (all 2D scenes and scripts unchanged).
**Verdict:** Phase 3D-2 COMPLETE. All acceptance gates pass.

---

## 1. What was built

**`scripts/grid_cell_library.gd`** — a procedural `MeshLibrary` built from `BoxMesh` primitives, one item per authoritative 48-unit tile: floor shadow, floor lit, wall variant A, wall variant B. Each item carries a matching `BoxShape3D` collision shape. No external meshes or textures are used, so the 3D level stays fully procedural like the 2D prototype.

**`scripts/level_generator_3d.gd`** — a `GridMap` generator that maps the authoritative grids from `level_catalog.gd` 1:1 onto 48-unit cells. Cell `(gx, gy)` maps to world `((gx+0.5)*48, y, (gy+0.5)*48)`, identical to the 2D coordinate convention. It also places zone overlay plates and marker plates (spawn, terminal, extraction, enemy spawn, door) and returns a result dictionary: spawn, spawn cell, wall cells, lit cells, door cells, terminals, extraction, enemy spawns, counts, grid size, bounds and generation time.

`level_catalog.gd` is **read-only and unmodified**; its SHA-256 is pinned in the host checks (`27d10bd6...`).

**`scenes/main3d.tscn` / `scripts/main3d.gd`** — `LevelRoot3D` now carries the generator. On start the LEGACY layout is generated, the player is placed on the layout's spawn cell, and keys `1`/`2`/`3`/`4` switch LEGACY / LAYOUT_B / LAYOUT_C / seeded(7) for desktop testing.

## 2. Deterministic parity (exact cell-count match)

Counts are a pure per-character census of the source rows, so parity is structural rather than sampled.

| Layout | Walls (3D / 2D) | Walkable (3D / 2D) | GridMap cells | Generation |
|---|---|---|---|---|
| LEGACY | 142 / 142 | 306 / 306 | 448 | ~2.2 ms |
| LAYOUT_B | 127 / 127 | 321 / 321 | 448 | ~1.3 ms |
| LAYOUT_C | 103 / 103 | 345 / 345 | 448 | ~1.2 ms |
| seeded(7) | 341 / 341 | 107 / 107 | 448 | ~1.3 ms |
| seeded(42) | 275 / 275 | 173 / 173 | 448 | ~1.3 ms |

All generation times are far below the 150 ms budget (measured 1.2–2.5 ms).

## 3. Collision accuracy

- Sampled wall cells collide at wall height `y = 120`.
- Sampled floor cells collide at `y = 0`, continuous across cell boundaries (verified at cell centers and at intermediate positions).
- The player spawns on the spawn cell, settles on the floor and is physically blocked by walls (walk test into the north wall moves ~8 units and stops).

Two real bugs were found and fixed during this phase:

1. **GridMap vertical alignment.** GridMap centres cell `y = 0` at `y = CELL/2`, so the floor sat above the spawn point and the player fell through the level. Fixed by offsetting the GridMap node by `-CELL/2`.
2. **MeshLibrary shape contract.** `set_item_shapes` expects a flat `[shape, transform, ...]` array, not a nested `[[shape, transform]]`. The nested form produced partial collision (floor existed only near cell centres), which is why the player sank while moving. Both item types now use the flat form.

## 4. Test evidence (fresh runs this iteration)

| Suite | Result |
|---|---|
| 3D phase-2 acceptance (`tools/test_3d_phase2.gd`) | **50 / 50 PASS** |
| 3D phase-1 acceptance (`tools/test_3d_phase1.gd`) | **33 / 33 PASS** |
| 2D smoke test | **297 / 297 PASS** (unbroken) |
| Android build/signing host checks | **50 / 50 PASS** (was 40) |
| `validate_project.sh` | exit 0 (import + boot + smoke + 3D phase-1 + 3D phase-2 + host checks) |
| `layout_probe.gd` PROBE3D | parity=true and wall_collision=true for all five layouts |

`validate_project.sh` now runs both 3D suites, so any future regression in the 3D track fails the standard validation gate.

## 5. Release artifact

- Rebuilt from the current tree with the existing release keystore (identity preserved).
- Package `com.shadowprotocol.game`, versionName `0.1.0`, versionCode `1`, arm64-v8a.
- Certificate SHA-256 `74ec3b4ec475f65517f0676b30d801f9fc557a5bb733dcabd70a5f016c574a0b` (unchanged).
- apksigner v2 + v3 valid, debug certificate absent, ZIP integrity OK.
- APK SHA-256 `dc20e7bbfd298a275746027a9ab1b4a3541afdab16323bf205c762e7eca4439e`.
- The 3D scene set (`main3d`, `level_generator_3d`, `grid_cell_library`) is packed in the APK, but `main.tscn` remains the default main scene: the 2D prototype still launches on device.

## 6. Repository state

- Commit `48b774f` — "Phase 3D-2: GridMap level generation with 1:1 cell parity" — pushed to `main` and confirmed remotely.
- Files: 2 new scripts (+ uid), 1 new test (+ uid), `main3d.tscn`, `main3d.gd`, `test_3d_phase1.gd`, `layout_probe.gd`, `validate_project.sh`, `test_build_android_host.sh`, `roadmap.md`.
- No APK, keystore, password or credential file is committed.

## 7. Roadmap verification (mandatory gate)

- Checkboxes: **30 / 30 complete**, no open tasks.
- Phase headers: **8 original phases intact**, no ninth phase.
- Task IDs unique, 30 total.
- Focus line unchanged and accurate: final acceptance closed 2026-11-22.
- Two dated 3D programme notes present (3D-1, 3D-2), explicitly marked as a separate programme that does not alter the acceptance roadmap.

## 8. Known limitations

- 3D gameplay systems are not wired yet: lighting/stealth, enemies, mission objects and UI live in Phases 3D-3 to 3D-5.
- Zone overlays and markers are visual only; no gameplay logic consumes them yet.
- Wall visuals are single-box blocks (no trim geometry), intentional for the mobile performance budget.
- No device testing was performed for the 3D scene; the 3D track is desktop/headless-verified so far.

## 9. Next phase

Phase 3D-3 — StealthSystem 3D port (Vector3 refactor, grid `(x, z)`, regression parity with the 2D formulas). Awaiting owner approval before starting, per the agreed stop gates.
