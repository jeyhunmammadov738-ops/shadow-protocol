# Shadow Protocol — Hotfix 0.2.1 Report
**On-device bug fixes: touch joystick, spawn framing, full gameplay loop**

Date: 2026-11-24 · Commit: 429de0c · Engine: Godot 4.7.2
Release: 0.2.1 (versionCode 3), package `com.shadowprotocol.game`

## 1. Root causes (both confirmed in code, not guesses)

**1.1 The joystick vector never reached Player3D.**
`Main3D._ready()` connected `crouch_toggled`, `sprint_toggled` and
`interact_pressed`, but never called `player.set_touch_controls(touch_layer)`.
`Player3D._read_move_input()` only consults the touch layer when that
reference exists, so on Android it fell through to `Input.get_vector(...)`
with no keyboard attached. Buttons worked (they were wired), the camera
worked (its own rig), and movement was dead. Fixed by wiring the layer.

**1.2 Touch coordinates were not normalised to canvas space.**
`mobile_controls.gd` compares touch positions against Control geometry laid
out in canvas space, but with `stretch/mode="canvas_items"` on a 20:9 phone
the screen events can arrive in window pixels. The joystick zone is a hard
cut at 42% of the canvas width, so a genuine left-half drag could fall
outside it and the floating joystick never appeared. Added `to_canvas()`,
an idempotent per-event normalisation used by `_input()` and
`is_position_owned()`.

## 2. Four further real bugs found while testing the loop

- **SPRINT stayed latched.** The momentary button reset its visual state on
  release but never emitted `sprint_toggled(false)`.
- **An open door could not be closed again.** `find_interactable()` skipped
  doors that were already open.
- **Interaction priority was implicit.** Door vs terminal was resolved by a
  door-only tie rule; it is now an explicit priority (objective/extraction >
  closed door > open door), so a nearby door can never steal a terminal use.
- **Spawn camera had no room behind it.** The player spawned with a wall
  directly behind, collapsing the spring arm to ~25 units. The body now
  still sits exactly on the layout spawn tile (a phase-2 invariant) and
  faces the longest open corridor, while the camera lifts over the blocking
  wall (`BLOCKED_PITCH`) instead of only shortening, giving a playable
  over-the-shoulder view (~98 units) from the first frame.

Camera framing was also retuned: spring length 170, pitch -0.26, shoulder
offset 26 units.

## 3. New regression test: `tools/test_3d_touch.gd` (24 checks)

Simulates Android touch end to end through `Viewport.push_input(event, true)`.
Note for future work: `Input.parse_input_event()` does **not** reach Control
nodes in a headless `--script` run, which is why the first attempt reported
false failures.

Covered: the touch layer reaches Player3D; left-half drag activates the
joystick and displaces the capsule (>40 units); release recentres and stops
the player; right-half drag still rotates the camera; SPRINT press/release;
CROUCH latch/unlatch; USE opens and closes a door; USE hacks a terminal with
the correct resolved target; every objective completes through the USE
button; extraction unlocks and the mission succeeds; spawn faces an open
corridor; camera distance stays playable.

Wired into `tools/validate_project.sh` (now 13 steps).

## 4. Verification

| Gate | Result |
|---|---|
| 3D touch regression (new) | **24/24** |
| 3D phase-6 | 38/38 |
| 3D phase-5 | 49/49 |
| 3D phase-4 | 32/32 |
| 3D phase-3 | 20/20 |
| 3D phase-2 | 50/50 |
| 3D phase-1 | 33/33 |
| 2D smoke (prototype intact) | 297/297 |
| 3D benchmark | 14/14 |
| Android host checks | 113/113 |
| validate_project.sh | exit 0 |

The phase-1 test was normalised (spawn orientation is deliberately no
longer yaw 0) and its camera-distance floor relaxed to 80 units, because a
blocked arm legitimately sits closer while the lift keeps it usable.

## 5. Release artifact

`ShadowProtocol-v0.2.1-release.apk` (26.6 MB), signed with the existing
upload keystore: v2+v3 verified, certificate
`74ec3b4ec475f65517f0676b30d801f9fc557a5bb733dcabd70a5f016c574a0b`,
debug certificate absent, `arm64-v8a` only, versionName 0.2.1 /
versionCode 3.

APK SHA-256: `575fd3d546234ef85e9bec68528ae05a1e485bf03bf7530de6e4e58a5d026871`

## 6. What to check on the POCO X5 Pro 5G

1. Left thumb drag shows the floating joystick and the player walks.
2. Spawn view shows the corridor ahead, not a wall.
3. SPRINT stops when released; CROUCH toggles.
4. USE opens and closes a door, hacks a terminal, and the beacon unlocks.
5. Restart keeps HUD and objectives consistent.

## 7. Known limits

- Touch is verified headless through synthetic viewport events; the physical
  digitiser path still needs your device run.
- Camera lift-over is a fixed steep pitch, not a collision-aware sweep.
- Doors slide rather than swing; patrol routes do not path through doors.
- Headless metrics remain CPU-side; device GPU numbers come from D2/D3/D4/D16.
