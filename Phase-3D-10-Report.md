# Shadow Protocol — Phase 3D-10 Report
**Making the ported systems playable, and giving the guards their reactions**

Date: 2026-11-26 · Commits: `d226190` (branch `phase-3d-10`) + `badb110` (merge to `main`)
Release: 0.5.0 (versionCode 6), package `com.shadowprotocol.game`

## 1. Source access and repo hygiene

The authoritative web repo `jeyhunmammadov738-ops/shadow-protocol-web` was read
remotely through the GitHub REST API (tree listing plus `contents` on
`enemyAI.ts`, `soundEngine.ts`, `weapons.ts`, `types.ts`, `stealthSystem.ts`,
`TacticalHud.tsx`). No clone was created, no temporary directory remains, the
stale `ceyhunmammadov9599-tech` clone was not used, and the web repository was
never written to, branched, or pushed.

## 2. Priority 1 — weapons are playable now

| Piece | Detail |
|---|---|
| Input actions | `fire` (left mouse + Enter), `reload` (R), `cycle_fire_mode` (F) in `project.godot` |
| Touch buttons | FIRE (r58), RELOAD and MODE (r34) in `mobile_controls.gd`, all routed through `is_point_owned` |
| Layout proof | Zero button overlaps and correct ownership at **1280x720, 2340x1080, 2400x1080**; the left half still belongs to the joystick and the right drag zone stays free |
| Wiring | `Main3D._poll_weapon_input()` for keyboard, `bind_weapon_controls()` for the touch signals, both into `fire_weapon()` / `reload_weapon()` / `cycle_fire_mode()` |
| Fire behaviour | Ammo spent, cooldown/burst/reload gates respected, stealth noise published at the weapon's own radius, haptic + procedural report, hitscan damage against guards |
| HUD | Live weapon panel: slot + name, magazine/reserve, `SEMI` / `3-BURST` / `AUTO` / `BLADE`, `RELOADING`, owned-slot strip with the current slot bracketed |

## 3. Priority 2 — enemy reactions

- **Gunshot awareness** already flowed through `StealthSystem3D`; it is now
  proven end to end: a shot sends the nearest guard to the shot position, a
  duplicate quieter noise does not restart the investigation, and an alerted
  guard is never pulled away (visual contact wins).
- **Downed bodies**: `take_damage()` drives hp, a guard at zero hp enters
  `STATE_DOWNED`, stops acting, reports itself and leaves a body that
  squadmates within 520 units walk over to investigate.
- **SquadDirector** (new, 0.45 s tick): radio callouts
  (`broadcast_alert`) put squadmates into ALERT with the shared threat
  position, and with two or more alerted guards it pairs a suppressor with a
  flanker that repositions through cover.
- **Guards use cover**: investigating or searching guards without visual
  contact move to `CoverSystem.cover_positions()`, keeping the ported
  `WALL_COVER_FACTOR 0.62` / `LOW_COVER_FACTOR 0.55` math untouched.
- **Act-3 patrol**: the escalation flag closes the patrol loop (route reverses
  at the last waypoint) and raises patrol speed by 1.18x, inside the existing
  six-state FSM rather than replacing it.

## 4. Priority 3 — audio and HUD

- **SpatialAudio**: exact port of the web `computeSpatial` (quadratic-cubic
  rolloff `t*t*(0.28+0.72*t)`, +/-0.85 pan clamp with near blend, 460/42
  default ranges) plus a procedural voice bank synthesised at runtime:
  suppressed/loud/rifle reports, three footstep surfaces (concrete, metal,
  vent), impact, door, terminal and alarm. `FeedbackManager`'s five cues are
  untouched and still play.
- **SectorBlueprint**: a `Control` that draws the live sector with `_draw()`
  every frame: walls, floor, doors, terminals, extraction, guards (neutral /
  alert / downed colours) and the player, with a measured draw cost well under
  the frame budget in headless runs.

## 5. Real bugs found and fixed

1. **Camera compressed by guards**: guards shared physics layer 1 with the
   world, so a guard walking behind the player collapsed the spring arm.
   Actors now live on layer 2, the camera keeps mask 1 and also excludes actor
   RIDs explicitly.
2. **Camera pumping at wall edges**: the blocked-arm lift-over oscillated
   (blocked -> lift -> clear -> lower -> blocked), which pumped the view and
   made the phase-1 framing check intermittent (1 in 3 runs). The lift is now
   latched until the player moves 48 units or turns 0.35 rad; six consecutive
   phase-1 runs are green.
3. **Validation drift**: `validate_project.sh` mixed `[1/12]`...`[10/12]` with
   `[11/15]`...`[15/15]` and its closing line still claimed only "smoke + 3D
   phase-1". Labels are now `[1/16]`...`[16/16]` and the echo lists the real
   pipeline.

## 6. Verification (fresh, on the final tree)

| Gate | Result |
|---|---|
| **3D-10 (new)** | **73/73** |
| 3D-9 / 3D-8 / touch | 58/58, 25/25, 24/24 |
| 3D-6 / 5 / 4 / 3 / 2 / 1 | 38/38, 49/49, 32/32, 20/20, 50/50, 33/33 |
| 2D smoke (prototype intact) | 297/297 |
| 3D benchmark (no leaks after restarts) | 14/14 |
| Android host checks | **156/156** (baseline 136) |
| `import` / `--quit-after 180` | exit 0 |
| `tools/validate_project.sh` (16 steps) | exit 0 |

3D-10 covers: keyboard and simulated-touch fire/reload/mode, ammo and noise
radius per weapon, touch ownership at three aspect ratios, guard gunshot
investigation, downed bodies and squad noticing, radio alert propagation,
guard cover use, Act-3 escalation, spatial-audio math and voice bank, the live
weapon panel, the live SectorBlueprint and reload cleanliness.

## 7. Deliberately not ported

| Item | Reason |
|---|---|
| PBR textures, bloom, volumetric cones, particles (Priority 4) | The mobile budget rule still applies: realtime shadows off, no post-processing. Not traded for looks. |
| Full 3,500-line web audio engine | The spatial math and the event families that matter in 3D are ported; the remaining WebAudio graph (reverb buses, per-voice scheduling) has no Godot equivalent worth the frame budget. |
| Web "camera mode" | Removed from the web build in commit `9dd5048`; Godot has the TPS camera. |

## 8. Release artifact

`ShadowProtocol-v0.5.0-release.apk` (26.6 MB): v2+v3 signatures verified,
certificate `74ec3b4ec475f65517f0676b30d801f9fc557a5bb733dcabd70a5f016c574a0b`,
debug certificate absent, `arm64-v8a` only, versionName 0.5.0 /
versionCode 6. APKs and keystores stay outside the repository.

APK SHA-256: `c246eda21c199d98e85dcbaa411d19838b3f986738666eb8a2c94f7c8e6972d0`

## 9. Known limits (what still needs your phone)

- Everything above is headless/host evidence. **No device FPS is claimed.**
  The first real-device run still has to confirm the FIRE button ergonomics
  with a moving thumb, audio latency on Bluetooth, and thermal behaviour.
- Guards investigate, flank and take cover, but they do not return fire: the
  player cannot lose a firefight yet, only detection.
- Downed guards stay down for the mission; there is no revive or carry.
- The weapon HUD is fixed-size and not yet scaled by a UI-size setting.
- Melee uses the same hitscan path with a 68-unit reach, so it has no
  animation-driven hit timing.
