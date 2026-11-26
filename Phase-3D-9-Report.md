# Shadow Protocol — Phase 3D-9 Report
**Porting the web-only gameplay features into the Godot 4.7.2 Android build**

Date: 2026-11-26 · Commits: `1c0d1f1` (branch `phase-3d-9`) + `f347bf1` (merge to `main`)
Release: 0.4.0 (versionCode 5), package `com.shadowprotocol.game`

## 1. How the web repo was read

Read-only remote inspection through the GitHub REST API (tree listing plus
`contents` on the specific files needed). No clone was created, nothing was
written to the web repository, and no temporary directory remains — the
downloaded reference files were deleted after use and verified absent. The
web repository was not modified in any way.

Files consulted: `src/game/weapons.ts`, `src/game/types.ts`,
`src/game/stealthSystem.ts` (cover rules), plus the repository tree to
confirm the feature list.

## 2. What shipped

### 2.1 Modular weapon system — `scripts/weapon_system.gd`
Six weapons across six slots, ported with the web build's own balance
numbers rather than retuned:

| Slot | Weapon | Category | Modes | Mag/Reserve | Noise | CCTV |
|---|---|---|---|---|---|---|
| 1 | FN Five-seveN | pistol, suppressed | semi | 20 / 60 | 62 | – |
| 2 | SIG Sauer P226 | pistol | semi | 15 / 45 | 235 | – |
| 3 | HK MP5SD | SMG, suppressed | semi/burst/auto | 30 / 60 | 115 | – |
| 4 | HK416 | rifle | semi/burst/auto | 30 / 60 | 380 | yes |
| 5 | AK-47 | rifle | semi/auto | 30 / 60 | 430 | yes |
| 6 | Tactical Combat Knife | melee | melee | – | 28 | – |

Implemented: magazine + reserve ammo, reload duration and reserve draw,
per-mode cooldowns, 3-round burst with recovery gate, damage, recoil kick and
pitch, hip vs ADS spread, range, suppressed flag, `can_disable_cctv`,
`supports_emp`, ammo pickups with per-weapon reserve caps, fire-mode cycling
and the web HUD labels (`SEMI` / `3-BURST` / `AUTO` / `BLADE`). The mission
starts with the Five-seveN and the knife owned, everything else is loot.

### 2.2 Cover mechanics — `scripts/cover_system.gd`
Wall-corner cover anchors derived from the wall grid, waist-high low-cover
boxes, `WALL_COVER_FACTOR = 0.62` and `LOW_COVER_FACTOR = 0.55` exactly as the
web build, plus `cover_positions(actor, threat)` for AI hunker-down choices
and a grid line-walk occlusion test.

### 2.3 Security cameras and laser tripwires
`scripts/security_camera.gd`: base yaw, sweep arc and speed, range, FOV,
grid-based occlusion, EMP disabling, `spotted_player` signal.
`scripts/laser_tripwire.gd`: endpoint beam, on/off cycle with phase offset,
single-trip semantics while inside the beam, EMP disabling.

### 2.4 Facility entity data — `scripts/facility_catalog.gd`
Cameras (longest-sightline wall spots), tripwires (corridor crossings), hide
containers (dead ends), breakers, vent hatches, decoys and barricades are
**derived deterministically from the existing layout descriptor**. The tile
encoding is untouched, so every existing layout stays byte-identical and BFS
reachability validation is unaffected — nothing new blocks a cell.

### 2.5 Prop visuals — `scripts/prop_factory.gd`
All new entities are built from Godot primitives (zero external assets):
security camera with mount and lens, laser emitter, crate/locker, breaker box,
decoy, vent hatch, barricade, dropped weapon.

### 2.6 Integration in `main3d.gd`
Main3D owns the `WeaponSystem` and `CoverSystem`, spawns and ticks the
facility layer, routes camera alarms and tripwire trips into the existing
alarm/feedback channel (audio cue + haptic, tripwire advances detection), and
weapon fire publishes stealth noise at the weapon's own radius so suppressed
and loud weapons already behave differently for guard hearing.

## 3. Verification (all fresh, on the final tree)

| Gate | Result |
|---|---|
| **3D-9 (new)** | **58/58** |
| 3D-8 | 25/25 |
| 3D touch regression | 24/24 |
| 3D-6 / 5 / 4 / 3 / 2 / 1 | 38/38, 49/49, 32/32, 20/20, 50/50, 33/33 |
| 2D smoke (prototype intact) | 297/297 |
| 3D benchmark (no leaks after restarts) | 14/14 |
| Android host checks | **136/136** (was 123) |
| `import` / `--quit-after 180` | exit 0 |
| `tools/validate_project.sh` (15 steps) | exit 0 |

Three real bugs were caught by the new tests and fixed before delivery:
the burst-recovery gate did not actually block the next burst, cover
positions were searched around the threat instead of the actor, and the
tripwire beam test compared vertical distance so a torso-height beam never
tripped.

## 4. Deliberately not ported (and why)

| Item | Reason |
|---|---|
| Guard combat, downed bodies, SquadDirector, Act-3 patrol (Priority 1) | Needs a substantial FSM extension; the existing six-state FSM, vision and noise already work, and a rushed port would regress them. Next phase candidate. |
| Spatial procedural audio engine (~3,500 lines) | Out of scope for one phase; the five existing cues stay intact and weapon fire already reuses them. |
| SectorBlueprint HUD | Presentation-only; better built once the facility entity set is stable on device. |
| PBR textures, bloom, volumetrics, particles (Priority 3) | Excluded by the mobile budget rule: realtime shadows stay off and there is no post-processing. Documented as intentionally skipped. |
| Web "camera mode" | Removed in web commit `9dd5048`; Godot already has the TPS camera. |

## 5. Release artifact

`ShadowProtocol-v0.4.0-release.apk` (26.6 MB), signed with the existing
upload keystore: v2+v3 verified, certificate
`74ec3b4ec475f65517f0676b30d801f9fc557a5bb733dcabd70a5f016c574a0b`,
debug certificate absent, `arm64-v8a` only, versionName 0.4.0 /
versionCode 5.

APK SHA-256: `58a4cbf73554e3e2e9b4f07a6e9ca7ba0a794f50b83822d7cef410e5eae88709`

## 6. Branch and repository state

Work was committed on `phase-3d-9` (`1c0d1f1`) and merged into `main` with a
merge commit (`f347bf1`), so the usual main-branch review still works. The
branch is pushed and available for a pull request if you prefer that flow.
APKs and keystores remain outside the repository.

## 7. Known limits

- Weapons are fully simulated but have no touch FIRE button yet; firing is
  exposed as `main3d.fire_weapon()` and is wired to noise, not to a HUD
  control. That is the first follow-up if you want it playable on device.
- Cover reduces visibility but guards do not yet actively take cover.
- Camera and tripwire detection is grid-based (deterministic), not physics.
- Facility entities are derived, so their placement is deterministic per
  layout rather than hand-authored.
- No device FPS claim is made here; headless metrics are CPU-side only.
