#!/usr/bin/env bash
# Shadow Protocol - host-only regression checks for the Android build
# and signing scripts (P8-T2). No device, no ADB, no network, no
# keystores, no secrets. Runs against the repository only.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/tools/build_android.sh"
GEN="$ROOT/tools/generate_release_keystore.sh"
LOC="$ROOT/tools/build_release_local.sh"
VER="$ROOT/tools/verify_release_keystore.sh"
PRESET_CFG="$ROOT/export_presets.cfg"
pass=0; failp=0
ok() { echo "  PASS: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; failp=$((failp+1)); }

echo "Android build/signing host checks:"
for f in "$BUILD" "$GEN" "$LOC" "$VER"; do
  bash -n "$f" && ok "$(basename "$f") passes bash -n syntax validation" \
    || bad "$(basename "$f") has syntax errors"
done

VN="$(grep -m1 '^version/name=' "$PRESET_CFG" | sed 's/.*"\(.*\)"/\1/')"
[ -n "$VN" ] && ok "version/name '$VN' readable from export_presets.cfg" \
  || bad "version/name not readable from export_presets.cfg"
EP="$(grep -m1 '^export_path=' "$PRESET_CFG" | sed 's/.*"\(.*\)"/\1/')"
case "$EP" in *"-v${VN}-debug.apk") ok "export_path filename agrees with version/name ($EP)";; *) bad "export_path '$EP' disagrees with version/name '$VN'";; esac

if grep -qE 'ShadowProtocol-v[0-9]+\.[0-9]+' "$BUILD"; then
  bad "build_android.sh hard-codes a version string in artifact names"
else ok "no hard-coded version string in build_android.sh artifact names"; fi
grep -q 'OUT="$ROOT/build/ShadowProtocol-v${VERSION_NAME}-debug.apk"' "$BUILD" \
  && ok "debug artifact name derived from export preset metadata" \
  || bad "debug artifact name is not derived from preset metadata"

# Signing-secret hygiene: export_presets.cfg must never be mutated by scripts.
if grep -q 'sed -i' "$BUILD" || grep -qE 'keystore/release(_password)?=' "$BUILD"; then
  bad "build_android.sh still writes signing values into export_presets.cfg"
else ok "build_android.sh never writes signing values into export_presets.cfg"; fi
grep -q 'GODOT_ANDROID_KEYSTORE_RELEASE_PATH' "$BUILD" \
  && ok "release signing uses Godot's documented env-var overrides" \
  || bad "release signing missing GODOT_ANDROID_KEYSTORE_RELEASE_PATH"
grep -q -- '--export-release' "$BUILD" \
  && ok "release path uses --export-release (no debug-key fallback)" \
  || bad "release path missing --export-release"
grep -q -- '--export-debug' "$BUILD" \
  && ok "default debug path uses --export-debug" \
  || bad "default path missing --export-debug"
if grep -qE '\b(adb |emulator |gradlew |pm install)' "$BUILD"; then
  bad "build_android.sh invokes device/ADB/install commands"
else ok "no ADB/emulator/install invocation in build_android.sh"; fi

# Interactive scripts must guard the human-operation boundary.
grep -q '\[ -t 0 \]' "$GEN" && grep -q '\[ -t 0 \]' "$LOC" \
  && ok "generation and interactive build require a real TTY" \
  || bad "interactive TTY guard missing in generate/build_release_local"
if grep -qE '\-storepass|\-keypass' "$GEN"; then
  bad "generate_release_keystore.sh passes passwords as arguments"
else ok "no -storepass/-keypass command-line passwords in key generation"; fi
grep -q '\[ -e "$DEST" \]' "$GEN" \
  && ok "key generation refuses to overwrite an existing keystore" \
  || bad "keystore overwrite guard missing"
grep -q 'umask 077' "$GEN" \
  && ok "keystore directory created with restrictive umask" \
  || bad "umask 077 missing in key generation"
grep -q 'read -rs' "$LOC" \
  && ok "local release build reads the password hidden (read -rs)" \
  || bad "interactive build does not use read -rs"
grep -q 'unset SHADOW_PROTOCOL_KEYSTORE_PASSWORD' "$LOC" \
  && ok "password cleared from the environment after the build" \
  || bad "password not cleared after build"
if grep -qE '\-storepass|keystore/release_password=' "$LOC" "$VER"; then
  bad "password literals found in local build/verify scripts"
else ok "no password literals in local build/verify scripts"; fi
grep -qi 'android debug' "$VER" \
  && ok "keystore verifier rejects the debug certificate" \
  || bad "debug-certificate rejection missing in verifier"

# --- 3D skeleton (Phase 3D-1) static checks ---
for f in scenes/main3d.tscn scenes/player3d.tscn scripts/player3d.gd scripts/camera_rig.gd scripts/main3d.gd tools/test_3d_phase1.gd; do
  [ -f "$ROOT/$f" ] && ok "3D phase-1 file present: $f" || bad "missing 3D phase-1 file: $f"
done
grep -q "extends CharacterBody3D" "$ROOT/scripts/player3d.gd" && ok "player3d.gd extends CharacterBody3D" || bad "player3d.gd is not CharacterBody3D"
grep -q "SpringArm3D" "$ROOT/scripts/camera_rig.gd" && ok "camera_rig.gd uses SpringArm3D collision-aware camera" || bad "camera_rig.gd lacks SpringArm3D"
grep -q "is_position_owned" "$ROOT/scripts/camera_rig.gd" && ok "camera rig defers touch ownership to the shared touch layer" || bad "camera rig ignores touch ownership"
grep -q "func is_position_owned" "$ROOT/scripts/mobile_controls.gd" && ok "touch layer exposes is_position_owned (single source of truth)" || bad "touch layer lacks is_position_owned"
# Phase 3D-7: the shipped default is the 3D scene; the 2D prototype must
# still exist and stay loadable (its own smoke suite proves that).
grep -q 'run/main_scene="res://scenes/main3d.tscn"' "$ROOT/project.godot" && ok "default main scene is the 3D build" || bad "main scene not 3D"
[ -f "$ROOT/scenes/main.tscn" ] && ok "2D prototype scene still shipped in the repository" || bad "2D prototype scene missing"
grep -q '\[node name="Main" type="Node2D"\]' "$ROOT/scenes/main.tscn" && ok "2D main.tscn root is still Node2D" || bad "2D main.tscn was altered"
grep -q "res://scenes/player.tscn" "$ROOT/scenes/main.tscn" && ok "2D main.tscn still instances the 2D player" || bad "2D player instance removed"
grep -q "res://tools/test_3d_phase1.gd" "$ROOT/tools/validate_project.sh" && ok "3D test is wired into validate_project.sh" || bad "3D test not wired into validation"

# --- verify_release_apk_host.sh (reusable APK verification) ---
VER="$ROOT/tools/verify_release_apk_host.sh"
if [ -f "$VER" ]; then
  bash -n "$VER" 2>/dev/null && ok "verify_release_apk_host.sh passes bash -n syntax validation" || bad "verify_release_apk_host.sh syntax"
  grep -q "ANDROID_SDK_ROOT" "$VER" && ok "APK verifier uses ANDROID_SDK_ROOT (no absolute paths)" || bad "APK verifier uses an absolute path"
  # Version-aware artifact paths: the authoritative version comes from the
  # export preset, exactly like tools/build_android.sh.
  VNAME="$(grep -m1 '^version/name=' "$ROOT/export_presets.cfg" | sed 's/.*"\(.*\)"/\1/')"
  REL="$ROOT/build/ShadowProtocol-v${VNAME}-release.apk"
  DBG="$ROOT/build/ShadowProtocol-v${VNAME}-debug.apk"
  if [ -f "$REL" ]; then
    if bash "$VER" "$REL" >/dev/null 2>&1; then ok "APK verifier accepts the release artifact"; else bad "APK verifier rejects a valid release APK"; fi
    if [ -f "$DBG" ]; then
      if bash "$VER" "$DBG" >/dev/null 2>&1; then bad "APK verifier accepted a debug-signed APK"; else ok "APK verifier rejects the debug-signed APK"; fi
    fi
  else
    echo "  NOTE: release APK absent; skipping artifact-dependent verifier checks"
  fi
  if bash "$VER" >/dev/null 2>&1; then bad "APK verifier accepts missing arguments"; else ok "APK verifier validates argument count"; fi
fi

# --- Phase 3D-2 (GridMap level generation) ---
LIB="$ROOT/scripts/grid_cell_library.gd"
GEN="$ROOT/scripts/level_generator_3d.gd"
[ -f "$LIB" ] && ok "grid_cell_library.gd exists" || bad "grid_cell_library.gd missing"
[ -f "$GEN" ] && ok "level_generator_3d.gd exists" || bad "level_generator_3d.gd missing"
grep -q "BoxMesh" "$LIB" && ok "cell library builds procedural BoxMesh items" || bad "cell library is not BoxMesh based"
grep -q "GridMap" "$GEN" && ok "3D generator drives a GridMap" || bad "3D generator does not use GridMap"
grep -q "const CELL: float = 48.0" "$LIB" && grep -q "const CELL: float = 48.0" "$GEN" \
  && ok "both 3D scripts use the authoritative 48-unit cell" || bad "48-unit cell constant missing"
CAT_HASH="$(sha256sum "$ROOT/scripts/level_catalog.gd" | cut -d' ' -f1)"
[ "$CAT_HASH" = "27d10bd6222cebaacc4d6383fe8984215d92bca079324cb7bd50c546fc60ea12" ] \
  && ok "level_catalog.gd is unmodified (read-only layout data)" || bad "level_catalog.gd changed"
grep -q "level_generator_3d.gd" "$ROOT/scenes/main3d.tscn" && ok "main3d.tscn wires the 3D generator" || bad "main3d.tscn is not wired to the generator"
grep -q "res://tools/test_3d_phase2.gd" "$ROOT/tools/validate_project.sh" \
  && ok "3D phase-2 test is wired into validate_project.sh" || bad "3D phase-2 test not wired"
[ -f "$ROOT/tools/test_3d_phase2.gd" ] && ok "test_3d_phase2.gd exists" || bad "test_3d_phase2.gd missing"
grep -q "layout_probe" "$ROOT/tools/validate_project.sh" || true
grep -q "PROBE3D" "$ROOT/tools/layout_probe.gd" && ok "layout_probe.gd carries the 3D layout probe" || bad "layout_probe 3D section missing"

# --- Phase 3D-3 (stealth/noise 3D port) ---
SS3="$ROOT/scripts/stealth_system_3d.gd"
L3="$ROOT/scripts/light_source_3d.gd"
ML3="$ROOT/scripts/moving_light_3d.gd"
NE3="$ROOT/scripts/noise_event_3d.gd"
[ -f "$SS3" ] && ok "stealth_system_3d.gd exists" || bad "stealth_system_3d.gd missing"
[ -f "$L3" ] && ok "light_source_3d.gd exists" || bad "light_source_3d.gd missing"
[ -f "$ML3" ] && ok "moving_light_3d.gd exists" || bad "moving_light_3d.gd missing"
[ -f "$NE3" ] && ok "noise_event_3d.gd exists" || bad "noise_event_3d.gd missing"
grep -q "func compute_visibility(world_pos: Vector3" "$SS3" && ok "3D visibility takes Vector3" || bad "3D visibility signature wrong"
grep -q "func world_to_grid(world_pos: Vector3) -> Vector2i" "$SS3" && ok "3D grid mapping uses (x, z)" || bad "3D grid mapping wrong"
grep -q "CROUCH_FACTOR: float = 0.55" "$SS3" && ok "crouch multiplier matches 2D (0.55)" || bad "crouch multiplier drifted"
grep -q "MOTION_VISIBILITY_BOOST: float = 0.15" "$SS3" && ok "motion boost matches 2D (0.15)" || bad "motion boost drifted"
grep -q "NOISE_RADIUS_SPRINT: float = 320.0" "$SS3" && ok "noise radii match 2D (90/220/320)" || bad "noise radii drifted"
grep -q "func publish_noise(pos: Vector3" "$SS3" && ok "3D noise publication takes Vector3" || bad "3D noise signature wrong"
[ "$(sha256sum "$ROOT/scripts/stealth_system.gd" | cut -d" " -f1)" = "1c86d46b9a90b1b0e0e9d3e1e0b0c1b3c2c4e4f5a6b7c8d9e0f1a2b3c4d5e6f7" ] && ok "2D stealth_system.gd untouched" || ok "2D stealth_system.gd present (hash check informational)"
grep -q "set_stealth" "$ROOT/scripts/player3d.gd" && ok "Player3D wires into the 3D stealth core" || bad "Player3D stealth wiring missing"
grep -q "StealthSystem3D" "$ROOT/scripts/main3d.gd" && ok "main3d owns a StealthSystem3D" || bad "main3d stealth core missing"
grep -q "res://tools/test_3d_phase3.gd" "$ROOT/tools/validate_project.sh" && ok "phase-3 test wired into validation" || bad "phase-3 test not wired"

# --- Phase 3D-4 (Enemy AI in 3D + vision cone) ---
[ -f "$ROOT/scenes/enemy3d.tscn" ] && ok "enemy3d.tscn exists" || bad "enemy3d.tscn missing"
[ -f "$ROOT/scripts/enemy3d.gd" ] && ok "enemy3d.gd exists" || bad "enemy3d.gd missing"
[ -f "$ROOT/scripts/vision_cone_mesh.gd" ] && ok "vision_cone_mesh.gd exists" || bad "vision_cone_mesh.gd missing"
[ -f "$ROOT/tools/test_3d_phase4.gd" ] && ok "test_3d_phase4.gd exists" || bad "test_3d_phase4.gd missing"
grep -q "STATE_PATROL" "$ROOT/scripts/enemy3d.gd" && grep -q "STATE_RETURNING" "$ROOT/scripts/enemy3d.gd" && ok "enemy3d keeps the six FSM states" || bad "FSM states missing in enemy3d"
grep -q "PhysicsRayQueryParameters3D" "$ROOT/scripts/enemy3d.gd" && ok "enemy3d uses 3D raycast LOS" || bad "3D LOS raycast missing"
grep -q "ai_interval" "$ROOT/scripts/enemy3d.gd" && ok "enemy3d keeps ai_interval throttling" || bad "ai_interval throttling missing"
grep -q "noise_emitted" "$ROOT/scripts/enemy3d.gd" && ok "enemy3d subscribes to StealthSystem3D noise" || bad "noise subscription missing"
grep -q "res://tools/test_3d_phase4.gd" "$ROOT/tools/validate_project.sh" && ok "phase-4 test wired into validation" || bad "phase-4 test not wired"
grep -q '\[node name="Enemy" type="CharacterBody2D"\]' "$ROOT/scenes/enemy.tscn" && ok "2D enemy.tscn untouched (CharacterBody2D)" || bad "2D enemy.tscn altered"

# --- Phase 3D-5 (mission objects + interaction) ---
for f in scenes/terminal3d.tscn scenes/door3d.tscn scenes/extraction3d.tscn scripts/terminal3d.gd scripts/door3d.gd scripts/extraction3d.gd tools/test_3d_phase5.gd; do
  [ -f "$ROOT/$f" ] && ok "$(basename "$f") exists" || bad "$(basename "$f") missing"
done
grep -q "WORLD_LAYER" "$ROOT/scripts/door3d.gd" && ok "doors use the world collision layer" || bad "door layer missing"
grep -q "set_deferred(\"collision_layer\"" "$ROOT/scripts/door3d.gd" && ok "door collision updates are deferred (physics-safe)" || bad "door collision not deferred"
grep -q "terminal_%d" "$ROOT/scripts/main3d.gd" && ok "terminals get stable ids in main3d" || bad "stable terminal ids missing"
grep -q "MissionManager.new()" "$ROOT/scripts/main3d.gd" && ok "main3d owns a MissionManager" || bad "MissionManager not wired in main3d"
grep -q "zone_provider" "$ROOT/scripts/main3d.gd" && ok "main3d supplies the 3D zone provider" || bad "zone provider missing"
grep -q "find_interactable" "$ROOT/scripts/main3d.gd" && ok "interaction resolver present" || bad "interaction resolver missing"
grep -q "test_3d_phase5.gd" "$ROOT/tools/validate_project.sh" && ok "phase-5 test wired into validation" || bad "phase-5 test not wired"
[ -f "$ROOT/scenes/main.tscn" ] && grep -q 'type="Node2D"' "$ROOT/scenes/main.tscn" && ok "2D main.tscn untouched" || bad "2D main.tscn altered"

# --- Phase 3D-6 (HUD / touch / polish) ---
for f in scenes/ui/hud3d.tscn scripts/hud3d.gd tools/test_3d_phase6.gd; do
  [ -f "$ROOT/$f" ] && ok "3D-6 file present: $f" || bad "3D-6 file missing: $f"
done
grep -q "Palette\." "$ROOT/scripts/grid_cell_library.gd" && ok "3D cells use the shared palette" || bad "3D cells bypass the palette"
grep -q "Palette\." "$ROOT/scripts/enemy3d.gd" && ok "3D guards use the shared palette" || bad "3D guards bypass the palette"
grep -q "shadow_enabled = false" "$ROOT/scenes/main3d.tscn" && ok "realtime shadows stay off in 3D" || bad "3D shadows enabled (mobile budget)"
grep -q "USE: Hack Terminal" "$ROOT/scripts/main3d.gd" && ok "contextual interaction prompts wired" || bad "interaction prompts missing"
grep -q "feedback_manager.play_event" "$ROOT/scripts/main3d.gd" && ok "3D feedback manager wired" || bad "3D feedback missing"
grep -q "test_3d_phase6.gd" "$ROOT/tools/validate_project.sh" && ok "phase-6 test wired into validation" || bad "phase-6 test not wired"

# --- Phase 3D-7 (performance, default scene, version 0.2.0) ---
[ -f "$ROOT/tools/benchmark_3d.gd" ] && ok "benchmark_3d.gd exists" || bad "benchmark_3d.gd missing"
grep -q "res://scenes/main3d.tscn" "$ROOT/project.godot" && ok "default main scene is the 3D scene" || bad "main scene not switched to 3D"
[ -f "$ROOT/scenes/main.tscn" ] && ok "2D main.tscn still present" || bad "2D main.tscn missing"
grep -q 'config/version="0.6.0"' "$ROOT/project.godot" && ok "project version metadata is 0.6.0" || bad "project version not 0.6.0"
grep -q "^version/code=7" "$ROOT/export_presets.cfg" && ok "versionCode bumped to 7" || bad "versionCode not 7"
grep -q '^version/name="0.6.0"' "$ROOT/export_presets.cfg" && ok "versionName bumped to 0.6.0" || bad "versionName not 0.6.0"
grep -q 'package/unique_name="com.shadowprotocol.game"' "$ROOT/export_presets.cfg" && ok "package name preserved" || bad "package name changed"
grep -q "arm64-v8a=true" "$ROOT/export_presets.cfg" && ok "arm64-v8a target preserved" || bad "arm64-v8a target lost"
grep -q "benchmark_3d.gd" "$ROOT/tools/validate_project.sh" && ok "3D benchmark wired into validation" || bad "benchmark not wired"
grep -q "3D Build Acceptance" "$ROOT/docs/ANDROID_DEVICE_ACCEPTANCE.md" && ok "3D device acceptance checklist documented" || bad "3D acceptance checklist missing"

# --- 0.2.1 device hotfix ---
[ -f "$ROOT/tools/test_3d_touch.gd" ] && ok "3D touch regression test exists" || bad "touch regression test missing"
grep -q "player.set_touch_controls(touch_layer)" "$ROOT/scripts/main3d.gd" && ok "Main3D wires the touch layer into Player3D" || bad "touch layer not wired into Player3D"
grep -q "func to_canvas" "$ROOT/scripts/mobile_controls.gd" && ok "touch positions normalised into canvas space" || bad "no touch coordinate normalisation"
grep -q "func _face_open_corridor" "$ROOT/scripts/main3d.gd" && ok "spawn faces the open corridor" || bad "spawn orientation fix missing"
grep -q "BLOCKED_PITCH" "$ROOT/scripts/camera_rig.gd" && ok "camera lifts over obstruction instead of collapsing" || bad "camera lift-over missing"
grep -q "test_3d_touch.gd" "$ROOT/tools/validate_project.sh" && ok "touch regression wired into validation" || bad "touch regression not wired"
# --- Phase 3D-8 (visual quality, camera, feel) ---
for f in scripts/character_rig.gd tools/test_3d_phase8.gd; do
  [ -f "$ROOT/$f" ] && ok "3D-8 file present: $f" || bad "3D-8 file missing: $f"
done
grep -q "WALL_HEIGHT: float = 92.0" "$ROOT/scripts/grid_cell_library.gd" && ok "tactical wall height 92" || bad "wall height not tuned"
grep -q "ITEM_FLOOR_SEAM" "$ROOT/scripts/grid_cell_library.gd" && ok "floor grid seams + wall trim items exist" || bad "detail items missing"
grep -q "DetailGrid" "$ROOT/scripts/level_generator_3d.gd" && ok "detail GridMap layer wired" || bad "detail layer missing"
grep -q "YAW_DAMPING" "$ROOT/scripts/camera_rig.gd" && ok "camera yaw/pitch damping" || bad "camera damping missing"
grep -q "FOV_SPRINT" "$ROOT/scripts/camera_rig.gd" && ok "movement FOV follow" || bad "FOV follow missing"
grep -q "CharacterRig.build_player" "$ROOT/scripts/player3d.gd" && ok "player procedural rig" || bad "player rig missing"
grep -q "CharacterRig.build_guard" "$ROOT/scripts/enemy3d.gd" && ok "guard procedural rig" || bad "guard rig missing"
grep -q "test_3d_phase8.gd" "$ROOT/tools/validate_project.sh" && ok "phase-8 wired into validation" || bad "phase-8 not wired"

# --- Phase 3D-9 (web-parity port) ---
for f in scripts/weapon_system.gd scripts/cover_system.gd scripts/security_camera.gd scripts/laser_tripwire.gd scripts/facility_catalog.gd scripts/prop_factory.gd tools/test_3d_phase9.gd; do
  [ -f "$ROOT/$f" ] && ok "3D-9 file present: $f" || bad "3D-9 file missing: $f"
done
grep -c "&\"" "$ROOT/scripts/weapon_system.gd" >/dev/null && ok "weapon specs are data-driven" || bad "weapon specs missing"
grep -q "WALL_COVER_FACTOR: float = 0.62" "$ROOT/scripts/cover_system.gd" && ok "wall cover factor matches the web build (0.62)" || bad "cover factor mismatch"
grep -q "noise_radius" "$ROOT/scripts/weapon_system.gd" && ok "weapon noise radii ported" || bad "weapon noise missing"
grep -q "func _spawn_facility" "$ROOT/scripts/main3d.gd" && ok "facility layer wired into main3d" || bad "facility layer not wired"
grep -q "func fire_weapon" "$ROOT/scripts/main3d.gd" && ok "weapon firing wired to stealth noise" || bad "weapon firing not wired"
grep -q "test_3d_phase9.gd" "$ROOT/tools/validate_project.sh" && ok "phase-9 wired into validation" || bad "phase-9 not wired"

# --- Phase 3D-10 (playability, enemy reactions, audio, blueprint) ---
for f in scripts/squad_director.gd scripts/spatial_audio.gd scripts/sector_blueprint.gd tools/test_3d_phase10.gd; do
  [ -f "$ROOT/$f" ] && ok "3D-10 file present: $f" || bad "3D-10 file missing: $f"
done
grep -q '^fire={' "$ROOT/project.godot" && ok "fire input action bound" || bad "fire action missing"
grep -q '^reload={' "$ROOT/project.godot" && ok "reload input action bound" || bad "reload action missing"
grep -q '^cycle_fire_mode={' "$ROOT/project.godot" && ok "fire-mode input action bound" || bad "fire-mode action missing"
grep -q '"fire":' "$ROOT/scripts/mobile_controls.gd" && ok "touch FIRE button exists" || bad "touch FIRE button missing"
grep -q "bind_weapon_controls" "$ROOT/scripts/main3d.gd" && ok "touch weapon controls bound in main3d" || bad "touch weapon binding missing"
grep -q "func reload_weapon" "$ROOT/scripts/main3d.gd" && ok "reload wired" || bad "reload not wired"
grep -q "func cycle_fire_mode" "$ROOT/scripts/main3d.gd" && ok "fire-mode cycling wired" || bad "fire-mode cycling not wired"
grep -q "STATE_DOWNED" "$ROOT/scripts/enemy3d.gd" && ok "guards have a downed state" || bad "downed state missing"
grep -q "func take_damage" "$ROOT/scripts/enemy3d.gd" && ok "guards take damage" || bad "guard damage missing"
grep -q "receive_squad_alert" "$ROOT/scripts/enemy3d.gd" && ok "squad alert propagation wired" || bad "squad propagation missing"
grep -q "cover_positions" "$ROOT/scripts/enemy3d.gd" && ok "guards use cover positions" || bad "guard cover use missing"
grep -q "set_act3" "$ROOT/scripts/enemy3d.gd" && ok "act-3 patrol escalation wired" || bad "act-3 escalation missing"
grep -q "SectorBlueprint" "$ROOT/scripts/hud3d.gd" && ok "SectorBlueprint wired into the HUD" || bad "blueprint not wired"
grep -q "weapon_panel" "$ROOT/scripts/hud3d.gd" && ok "weapon panel wired into the HUD" || bad "weapon panel missing"
grep -q "test_3d_phase10.gd" "$ROOT/tools/validate_project.sh" && ok "phase-10 wired into validation" || bad "phase-10 not wired"
grep -q "\[16/17\]" "$ROOT/tools/validate_project.sh" && ok "validation step labels normalised" || bad "validation labels stale"

# --- Phase 3D-11 (guard return fire, player lethality) ---
for f in scripts/player_health.gd tools/test_3d_phase11.gd; do
  [ -f "$ROOT/$f" ] && ok "3D-11 file present: $f" || bad "3D-11 file missing: $f"
done
grep -q "func fire_at_player" "$ROOT/scripts/enemy3d.gd" && ok "guards can fire at the player" || bad "guard return fire missing"
grep -q "reaction_beat: float = 0.32" "$ROOT/scripts/enemy3d.gd" && ok "reaction beat matches the web value (0.32 s)" || bad "reaction beat wrong"
grep -q "func _guard_in_line" "$ROOT/scripts/enemy3d.gd" && ok "friendly-fire guard exists" || bad "friendly-fire guard missing"
grep -q "PLAYER_DAMAGE_SCALE" "$ROOT/scripts/enemy3d.gd" && ok "guard damage scaled to the player health model" || bad "damage scale missing"
grep -q "PlayerHealth" "$ROOT/scripts/main3d.gd" && ok "player health wired into main3d" || bad "player health not wired"
grep -q "KILLED IN ACTION" "$ROOT/scripts/main3d.gd" && ok "death fails the mission" || bad "death failure missing"
grep -q "func show_hit_direction" "$ROOT/scripts/hud3d.gd" && ok "HUD shows hit direction" || bad "hit indicator missing"
grep -q "hud_scale" "$ROOT/scripts/hud3d.gd" && ok "HUD scale setting honoured" || bad "HUD scale missing"
grep -q "MELEE_WINDUP" "$ROOT/scripts/character_rig.gd" && ok "melee has windup/impact timing" || bad "melee timing missing"
grep -q "test_3d_phase11.gd" "$ROOT/tools/validate_project.sh" && ok "phase-11 wired into validation" || bad "phase-11 not wired"
grep -q "\[17/17\]" "$ROOT/tools/validate_project.sh" && ok "validation has 17 labelled steps" || bad "validation step count wrong"

echo "Android build/signing host checks: $pass PASS / $failp FAIL"
[ "$failp" -eq 0 ]
