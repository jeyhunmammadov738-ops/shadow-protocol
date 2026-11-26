# Shadow Protocol — Phase 3D-11 Report
**Guards return fire, the player can lose a firefight, and the tests tell the truth**

Date: 2026-11-26 · Commits: `d5fa604` (branch `phase-3d-11`), `89a1f45` (merge to `main`), report commit below
Release: 0.6.0 (versionCode 7), package `com.shadowprotocol.game`

## 1. Source access and hygiene

The authoritative web repo `jeyhunmammadov738-ops/shadow-protocol-web` was read
remotely through the GitHub REST API (tree listing plus `contents` on
`enemyAI.ts`, `gameEngine.ts`, `weapons.ts`, `types.ts`, `stealthSystem.ts`).
**The web repository was never cloned, branched, committed to or written in any
way**, the stale `ceyhunmammadov9599-tech` clone was not used, and no temporary
directory remains (the downloaded reference files were deleted and verified
absent).

## 2. Premise check: this is a new feature, not a parity port

The prompt asked me to verify whether the web build damages the player. It does
not:

- `gameEngine.ts` has exactly two `applyBallisticHit` call sites (lines **4205**
  and **4613**), both passing `this.playerPos`, i.e. player shots hitting guards.
- `enemyAI.ts` has no player-damage path: no `playerHealth`, no
  `damagePlayer`, no guard-to-player hit resolution. `weaponId` (default
  `hk416`) is used for display and reload/interval bookkeeping only.

Guard return fire is therefore a **new feature designed from existing web
primitives**: the shared weapon specs, `REACTION_BEAT_SEC = 0.32`, the LOS
raycast the vision cone already uses, the ported cover factors, the
`SquadDirector` roles and the noise channel.

## 3. What shipped

### 3.1 Guard weapons and fire gates (`scripts/enemy3d.gd`)

- `set_weapon()` reads `WeaponSystem.SPECS` (no duplicated stat tables), so a
  guard inherits HK416 damage 1.4, mag 30, range 960, noise 380, cooldowns and
  reload time from the same source the player uses.
- Every gate is mandatory before a round leaves the barrel: ALERT state, not
  downed, not reloading, magazine non-empty, cooldown and burst timers clear,
  target inside the spec's `range`, unobstructed LOS via the existing vision
  raycast, no squadmate in the firing line, and the **0.32 s reaction beat**
  elapsed (staggered by up to 0.12 s per guard so a squad never fires on one
  frame).
- `hit_chance()` is derived from perception, not an unrelated roll: base
  accuracy falls with distance, scales with `detection_strength()` (light,
  shadow, crouch, motion) and is multiplied by the cover factor. The roll is a
  per-guard seeded LCG, so a fixed seed reproduces every outcome exactly.
- Misses still publish gunshot noise at the weapon's own radius and play a
  spatial report, so stealth and audio stay consistent.
- A downed guard holds fire, cannot be hit again, and cannot shoot.

### 3.2 Squad tactics

`_assign_combat_roles()` (main3d) and the existing `SquadDirector` keep exactly
one suppressor per engagement: it holds its position to keep the firing line
steady while the rest keep repositioning through `CoverSystem.cover_positions()`.
The six-state FSM and the 0.45 s director tick are unchanged.

### 3.3 Player health and failure (`scripts/player_health.gd`)

- 100 HP + 40 armour; armour absorbs 70% of each hit; a 0.55 s post-hit grace
  window; delayed regeneration (6 s delay, 4 HP/s); damage scaled by the cover
  factor, so crouching behind low cover genuinely helps.
- Guard weapon damage is authored on the guard scale (a guard dies at hp 3.0),
  so `PLAYER_DAMAGE_SCALE = 12.0` maps it onto the player's pool while keeping
  the web ratios between weapons intact.
- Feedback: HUD `HP / ARM` readout (turns red below 30), directional hit wedge
  relative to camera yaw, red damage flash, a new `shot_guard` procedural voice
  plus an `impact` cue. `FeedbackManager`'s five cues are untouched.
- Zero health emits `died()`, sets `player_dead`, fails the mission with
  **KILLED IN ACTION**, and the existing restart action plus `load_layout()`
  restores health, clears the death flag and rebuilds a clean squad.

### 3.4 Polish items from Priority 3

- **HUD scaling**: panel and blueprint offsets and font sizes multiply by
  `shadow_protocol/hud_scale` (0.75–1.6) instead of fixed absolute values.
- **Melee timing**: the rig now has a windup (0.18 s), an impact frame and a
  recovery (0.24 s); `main3d` defers damage to the impact frame. The 68-unit
  reach is unchanged.
- **Revive/carry** for downed guards is deliberately left open (see §6).

## 4. Test integrity repairs

Two assertions in `tools/test_3d_phase10.gd` were tautological and are now real:

| Old assertion | New assertion |
|---|---|
| `current_mode() != before or current_mode() == 0` — passed even when nothing changed | the keyboard path must change the mode, and a second cycle must move again |
| `cover_moves >= before` and `spots.size() > 0 or cover_moves == before` — passed with zero cover moves | a wall stand-off is staged, `cover_positions()` must return positions, `cover_moves` must increase, and the guard's target must be one of those positions |

The strengthened suite went from **73 to 75 executed checks** and still passes.
The rest of the suite was reviewed for self-satisfying checks; none remained.

## 5. Verification (measured on this tree)

| Gate | Command | Result |
|---|---|---|
| 3D-11 (new) | `--script res://tools/test_3d_phase11.gd` | **44 PASS / 0 FAIL** |
| 3D-10 (strengthened) | `--script res://tools/test_3d_phase10.gd` | **75 PASS / 0 FAIL** |
| 3D-9 / 3D-8 / touch | scripts | 58 / 25 / 24, all 0 FAIL |
| 3D-6 / 5 / 4 / 3 / 2 / 1 | scripts | 38 / 49 / 32 / 20 / 50 / 33, all 0 FAIL |
| 2D smoke | `res://tools/smoke_test.tscn` | **297 PASS** |
| 3D benchmark | `--script res://tools/benchmark_3d.gd` | **14 PASS / 0 FAIL**, no leaks after restarts |
| Android host checks | `tools/test_build_android_host.sh` | **169 PASS / 0 FAIL** (baseline 156) |
| import | `--headless --path . --import` | exit **0** |
| 180 frames | `--headless --path . --quit-after 180` | exit **0** |
| full pipeline | `tools/validate_project.sh` (17 steps) | exit **0** |

3D-11 covers: LOS + range gating, no shot through a wall, the reaction beat,
magazine depletion and reload, spec-exact noise radius, the spatial-audio
event, suppressor/flanker assignment, damage only from landed unblocked hits,
cover reducing damage, the live HUD readout, death → MISSION FAILED → clean
restart, downed guards holding fire, friendly-fire blocking, restart leaving
exactly one `SpatialAudio` with a matching squad registry, and a repeat-run
determinism comparison.

## 6. Deliberately not ported / still open

| Item | Reason |
|---|---|
| Revive or carry for downed guards | Priority 3 explicitly allows deferral; adding it would touch the FSM and squad paths that Priority 1–2 depend on. |
| Guard suppression fire without LOS | A guard without LOS holds fire by design; simulated suppression would need a new ammo-cost model and is not in the web build. |
| Web "camera mode" | Removed upstream in `9dd5048`. |
| PBR/bloom/volumetrics | Still excluded by the mobile budget (no realtime shadows, no post-processing). |

## 7. Release artifact

`ShadowProtocol-v0.6.0-release.apk` — 26,984,325 bytes (25.7 MB), signed with
the existing upload keystore: v2+v3 signatures verified, certificate
`74ec3b4ec475f65517f0676b30d801f9fc557a5bb733dcabd70a5f016c574a0b`, debug
certificate absent, `arm64-v8a` only, versionName 0.6.0 / versionCode 7.
APKs and keystores stay outside the repository.

APK SHA-256: `7aa1ceaada1c0919d9e9b4b481e1e108a6d00c582afb2b963b540b17b9027083`

## 8. Device validation checklist (nothing here is a device claim)

1. **FIRE ergonomics**: hold the phone one-handed and fire while steering with
   the left thumb. The button sits 268 units up from the bottom edge; confirm it
   is reachable without moving your grip.
2. **Audio latency**: fire a suppressed Five-seveN shot and a guard HK416 burst
   on Bluetooth headphones; the report should follow the muzzle flash, not lag.
3. **Firefight fairness**: trigger an alert in a corridor and break line of
   sight. You should survive the opening burst (armour absorbs 70%) and reach
   cover; report if death feels instant.
4. **Thermal/FPS**: five minutes of continuous alert with two guards firing.
   No FPS number is claimed in this report, only what you measure.
5. **Death and restart**: let health reach zero, confirm MISSION FAILED, then
   restart and confirm full health, no leftover audio and guards back on patrol.

## 9. Known limits

- All evidence above is headless/host CPU-side. **No device FPS, thermal or
  latency figures are claimed.**
- Guard accuracy is deterministic per seed, so repeated identical engagements
  play out identically; that is deliberate for testability, not a design ideal.
- Armour does not regenerate during a mission, only health after 6 s.
- The HUD scale setting is read once at HUD construction.
