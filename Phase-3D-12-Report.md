# Shadow Protocol — Phase 3D-12 Report
**Test-integrity repair and pipeline-label cleanup. No gameplay change.**

Date: 2026-11-26 · Version 0.6.1 / versionCode 8 · Godot 4.7.2.stable

| Commit | Role |
|---|---|
| `69c5d1c` | phase-3d-12 feature commit |
| `617d741` | merge into `main` |
| report commit | this file (see `git log --oneline -1` on `main`) |

## 1. Source access and hygiene

- Only `jeyhunmammadov738-ops/shadow-protocol` was modified.
- The private web repository was **not accessed at all** in this phase: no API
  call, no clone, no branch, no write. Nothing to undo, nothing to clean.
- No temporary directory was created. `ls /tmp | grep -E "websrc|w1[01]"` → empty.
- No gameplay file changed except the version metadata. `scripts/enemy3d.gd`,
  `scripts/player_health.gd`, `scripts/hud3d.gd` and `scripts/main3d.gd` are
  byte-identical to 0.6.0.

## 2. Priority 1 — pipeline numbering

Before: `[1/17] … [10/17] [12/17] [13/17] [13/17] [14/17] [15/17] [16/17] [17/17]`
(no 11, 13 twice).

After, grep proof:

```
$ grep -oE '\[[0-9]+/17\]' tools/validate_project.sh | tr '\n' ' '
[1/17] [2/17] [3/17] [4/17] [5/17] [6/17] [7/17] [8/17] [9/17] [10/17]
[11/17] [12/17] [13/17] [14/17] [15/17] [16/17] [17/17]
```

17 labels, all unique, ascending, no gaps. Only the two echo strings changed;
every command, gate and failure message is untouched. The host suite's own
"validation has 17 labelled steps" check passes.

## 3. Priority 2 — meaningless tests removed

| File | Before | After |
|---|---|---|
| `tools/test_3d_phase11.gd` (old line 99) | `_check(true, "closed-door occlusion shares the same LOS gate as walls")` | Real staging in `_door_occlusion()`: a real door object, `set_state(false)`, physics frames to let the deferred collision-layer change land, then `not can_fire_at(...)` and `fire_at_player(...).is_empty()`, then `set_state(true)` and the firing line must return. Runs on `layout_b`, restores the original layout, and prints `SKIP: …` if no layout qualifies. |
| `tools/test_3d_phase11.gd` (old line 276) | `_check(_digest.size() > 0, …)` — unfalsifiable, because `_check()` appends to the digest | Deleted. The PASS total now comes from `_checks`, the number of `_check()` invocations that actually executed. |
| `tools/test_3d_phase10.gd`, `tools/test_3d_phase11.gd` | tautology sweep for `_check(true, …)`, always-true disjunctions, counters asserted without action | None found remaining. The two 3D-10 assertions fixed in 3D-11 (real fire-mode change, real cover move) still hold. |

Why the door test is meaningful: `scripts/door3d.gd` sets
`collision_layer = WORLD_LAYER` while closed and `0` while open, and the guard's
LOS ray queries mask 1. A closed door therefore blocks the shot and an open one
does not — the assertion flips with behaviour. Both sides of the door are
checked to be open cells first, so a wall can never be the thing doing the
blocking.

## 4. Honest check counts

- `test_3d_phase11.gd`: **47 `_check(` occurrences**, one of which is the
  `func _check(` definition → **46 call sites**, **46 executed**. The three door
  checks are inside the door loop and ran once on `layout_b`; the `SKIP` branch
  did not run, so nothing is claimed for it. (3D-11 reported 44 because the
  `_check(true)` and `_digest` lines were counted but the door branch was a
  no-op; the honest number today is 46.)
- `test_3d_phase10.gd`: **60 occurrences − 1 definition = 59 call sites → 75
  executed**. The difference is loop expansion: the touch-button overlap matrix
  and the weapon-slot assertions run once per element (e.g. 6 slots, 3 aspect
  ratios).

## 5. Gate table (measured in this tree, Godot 4.7.2.stable)

Every row was executed on this machine with `/tmp/godot --headless --path .`.
`tools/validate_project.sh` → exit **0**, all 17 labels printed in order.

| Gate | Command | Result |
|---|---|---|
| import | `--import` | exit 0 |
| headless 180 frames | `--quit-after 180` | exit 0, no script errors |
| 2D smoke | `res://tools/smoke_test.tscn` | 297 PASS |
| 3D-1 | `test_3d_phase1.gd` | 33 PASS / 0 FAIL |
| 3D-2 | via validate | 50 PASS / 0 FAIL |
| 3D-3 | `test_3d_phase3.gd` | 20 PASS / 0 FAIL |
| 3D-4 | via validate | 32 PASS / 0 FAIL |
| 3D-5 | via validate | 49 PASS / 0 FAIL |
| 3D-6 | via validate | 38 PASS / 0 FAIL |
| 3D-10 | `test_3d_phase10.gd` | 75 PASS / 0 FAIL |
| 3D-11 | `test_3d_phase11.gd` | 46 PASS / 0 FAIL |
| 3D-9 | `test_3d_phase9.gd` | 58 PASS / 0 FAIL |
| 3D-8 | `test_3d_phase8.gd` | 25 PASS / 0 FAIL |
| touch | `test_3d_touch.gd` | 24 PASS / 0 FAIL |
| benchmark | `benchmark_3d.gd` | 14 PASS / 0 FAIL |
| Android host | `test_build_android_host.sh` | 169 PASS / 0 FAIL |

Not run in this phase: anything requiring a physical Android device
(ergonomics, audio latency, thermal, FPS). No FPS number is claimed here.

## 6. APK artifact

Built and verified outside the repository:

- File: `build/ShadowProtocol-v0.6.1-release.apk`, 26,984,325 bytes
- SHA-256: `2e77bcbbf66d591c2fc293c1e64f0231e0a97816e59e805274120a010c093fad`
- Package `com.shadowprotocol.game`, versionName 0.6.1, versionCode 8, arm64-v8a
- Signature verifies (v2+v3), release certificate fingerprint
  `74ec3b4ec475f65517f0676b30d801f9fc557a5bb733dcabd70a5f016c574a0b`, debug
  certificate not used — `tools/verify_release_apk_host.sh` prints
  `OK: … passes host-side release verification`.
- Delivered to the owner as a zip outside GitHub, per standing instruction.

Note: the byte size matches 0.6.0 because only test scripts and version
metadata changed; test scripts are not packaged into the APK.

## 7. What remains open

- Revive/carry for downed guards (never implemented; lower priority).
- Real device validation: FIRE-button ergonomics, Bluetooth audio latency,
  thermal behaviour, per-scenario device benchmarks.
- The `SKIP` path of the door test: no layout currently lacks a usable door, but
  the branch exists so a future layout without doors cannot silently pass.
