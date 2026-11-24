# Shadow Protocol — Phase 3D-6 Completion Report
**UI/Touch Adaptation + Visual Polish**

Date: 2026-11-24 · Commit: 6e2f49c · Engine: Godot 4.7.2 (mobile renderer)

## 1. Delivered

**3D HUD.** New `scenes/ui/hud3d.tscn` + `scripts/hud3d.gd`. The scene
instances the *same* scripts the 2D prototype ships — `visibility_meter.gd`,
`detection_meter.gd`, `warning_layer.gd`, `mission_overlay.gd` — so the
presentation language is identical, and adds the 3D-specific pieces: a
top-left mission status panel (objectives n/m, extraction LOCKED/READY,
mission state), a bottom-centre contextual prompt and a subtle centre reticle.

Live wiring (every frame, no polling stubs):
- `Player3D.visibility` → visibility meter
- `MissionManager.detection_timer / detection_grace` → detection meter and
  warning-layer edge ratio
- `MissionManager.objectives_done()/objectives_total()/extraction_available()/state`
  → status panel
- `Main3D.interaction_hint()` → prompt text plus reticle highlight

**Contextual prompts.** `Main3D.interaction_hint()` returns
`USE: Hack Terminal`, `USE: Open Door` or `REACH EXTRACTION` only when the
target is inside the interaction radius *and* has raycast line of sight; it
returns an empty string otherwise, and the reticle drops back to its idle tint.

**Touch + layout integrity.** Camera drag stays on the right half via the
single-source `is_point_owned` rule from 3D-1, so the left joystick and the
SPRINT/CROUCH/USE buttons keep exclusive ownership. Verified at 1280x720
(16:9), 2340x1080 (19.5:9) and 2400x1080 (20:9): no HUD element overlaps the
button cluster and every element stays fully inside the viewport.

**Visual polish (mobile-safe).** `Palette.gd` now drives 3D floors, walls
(two variants), terminals (amber available / green completed), doors
(slate closed / cyan open), the extraction beacon (locked/active/done) and
guard state colours. Realtime directional shadows are **off**; lighting is
ambient plus emissive materials only, with no post-processing and the same
low draw-call GridMap structure as 3D-2.

**Audio/haptics.** `FeedbackManager` is owned by `Main3D` and fires the
existing cue set: `terminal` (+80 ms haptic), `door` (+50 ms), `warning`
(+40 ms), `success` (+250 ms), `failure` (+180 ms). Mission end also drives
the shared `MissionOverlay` and hides the in-mission HUD.

## 2. Bug found and fixed during testing

The interaction prompt was anchored with `anchors_preset = 7` but without
`anchor_top/anchor_bottom = 1.0`, so its rect sat at negative Y — above the
screen. It would never have rendered in the shipped build. The automated
layout check caught it; the anchor is now bottom-centre (-140..-110 px).

## 3. Verification (all fresh, this run)

| Gate | Result |
|---|---|
| 3D phase-6 (new) | **38/38 PASS** |
| 3D phase-5 | 49/49 |
| 3D phase-4 | 32/32 |
| 3D phase-3 | 20/20 |
| 3D phase-2 | 50/50 |
| 3D phase-1 | 33/33 |
| 2D smoke | 297/297 |
| Host checks | 98/98 (was 89) |
| import / boot / validate_project.sh | exit 0 |

Phase-6 coverage: HUD components present, meter values follow live state,
status panel text/state, prompt appears and clears, reticle highlight, door
prompt on LAYOUT_C, layout non-overlap and containment at three aspect ratios,
terminal/door/failure/success audio cues, haptics, and clean restart
(objectives reset, extraction re-locked, prompt cleared, no duplicate objects).

## 4. Release artifact

Signed release APK rebuilt and host-verified (v2+v3 signature, release
certificate unchanged). SHA-256 `b8f3e36b99dd9f5b35e0ebe152db81bc8614385c1e8ee6d72af70a7ced4dfab1`.

## 5. Known limits

- HUD metrics are headless CPU; device GPU frame timing is Phase 3D-7.
- No door hinge animation (panel slides); patrol routes still do not cross doors.
- Reticle is a static dot (no target-lock animation).
- Default main scene remains the 2D prototype; `main3d.tscn` is run explicitly.

## 6. Stop gate

Phase 3D-6 is complete and pushed (commit 6e2f49c). Awaiting approval before
Phase 3D-7 (final 3D performance profiling, Android export path and device
acceptance).
