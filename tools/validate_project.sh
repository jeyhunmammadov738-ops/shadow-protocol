#!/usr/bin/env bash
# Shadow Protocol - headless project validation.
# Imports resources, boots the main scene for a few seconds of headless
# simulation and fails on any script/scene error. No display required.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
FRAMES="${FRAMES:-180}"   # ~3 seconds at 60 FPS of game logic
LOG="$(mktemp /tmp/shadow-protocol-validate.XXXXXX.log)"

if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
  echo "ERROR: Godot binary '$GODOT_BIN' not found." >&2
  echo "Set GODOT_BIN=/path/to/godot or install Godot 4.7.2." >&2
  exit 1
fi
echo "Using Godot: $($GODOT_BIN --version 2>&1 | head -n1)"

echo "[1/12] Importing resources..."
"$GODOT_BIN" --headless --path "$ROOT" --import >"$LOG" 2>&1 || {
  tail -n 40 "$LOG"; echo "ERROR: resource import failed."; exit 1; }

echo "[2/12] Running main scene headless for $FRAMES frames..."
"$GODOT_BIN" --headless --path "$ROOT" --quit-after "$FRAMES" >"$LOG" 2>&1 || {
  tail -n 60 "$LOG"; echo "ERROR: headless run failed."; exit 1; }

echo "[3/12] Scanning output for script and scene errors..."
if grep -nEi "script error|parse error|failed to load" "$LOG"; then
  echo "ERROR: errors detected during headless run."; exit 1
fi

echo "[4/12] Running headless smoke test (movement, crouch, joystick, stealth)..."
"$GODOT_BIN" --headless --path "$ROOT" res://tools/smoke_test.tscn >"$LOG" 2>&1 || {
  tail -n 40 "$LOG"; echo "ERROR: smoke test failed."; exit 1; }
grep -q "SMOKE TEST: all checks passed" "$LOG" || {
  tail -n 40 "$LOG"; echo "ERROR: smoke test did not pass."; exit 1; }

echo "[5/12] Running 3D phase-1 acceptance test (player, TPS camera, touch zones)..."
"$GODOT_BIN" --headless --path "$ROOT" --script res://tools/test_3d_phase1.gd >"$LOG" 2>&1 || {
  tail -n 60 "$LOG"; echo "ERROR: 3D phase-1 test failed."; exit 1; }
grep -q "3D PHASE-1 TEST: all checks passed" "$LOG" || {
  tail -n 60 "$LOG"; echo "ERROR: 3D phase-1 test did not pass."; exit 1; }

# Host-only Android build-script checks (P8-T2 naming/signing logic).
if [ -x "$ROOT/tools/test_build_android_host.sh" ]; then
  echo "[6/12] Running 3D phase-2 test (GridMap parity, collisions, spawn)..."
  "$GODOT_BIN" --headless --path "$ROOT" --script res://tools/test_3d_phase2.gd >"$LOG" 2>&1 || {
    tail -n 60 "$LOG"; echo "ERROR: 3D phase-2 test failed."; exit 1; }
  grep -E "3D PHASE-2 TEST:" "$LOG" || {
    tail -n 60 "$LOG"; echo "ERROR: 3D phase-2 test did not pass."; exit 1; }

  echo "[7/12] Running 3D phase-3 test (stealth/noise 2D-3D parity, integration)..."
  "$GODOT_BIN" --headless --path "$ROOT" --script res://tools/test_3d_phase3.gd >"$LOG" 2>&1 || {
    tail -n 60 "$LOG"; echo "ERROR: 3D phase-3 test failed."; exit 1; }
  grep -q "3D PHASE-3 TEST: all checks passed" "$LOG" || {
    tail -n 60 "$LOG"; echo "ERROR: 3D phase-3 parity did not pass."; exit 1; }

  echo "[8/12] Running 3D phase-4 test (enemy FSM, vision LOS, noise, stress)..."
  "$GODOT_BIN" --headless --path "$ROOT" --script res://tools/test_3d_phase4.gd >"$LOG" 2>&1 || {
    tail -n 60 "$LOG"; echo "ERROR: 3D phase-4 test failed."; exit 1; }
  grep -E "3D PHASE-4 TEST:" "$LOG" || {
    tail -n 60 "$LOG"; echo "ERROR: 3D phase-4 test did not pass."; exit 1; }

  echo "[9/12] Running 3D phase-5 test (mission objects, interaction, restarts)..."
  "$GODOT_BIN" --headless --path "$ROOT" --script res://tools/test_3d_phase5.gd >"$LOG" 2>&1 || {
    tail -n 60 "$LOG"; echo "ERROR: 3D phase-5 test failed."; exit 1; }
  grep -E "3D PHASE-5 TEST:" "$LOG" || {
    tail -n 60 "$LOG"; echo "ERROR: 3D phase-5 test did not pass."; exit 1; }

  echo "[10/12] Running 3D phase-6 test (HUD, prompts, layout integrity, feedback)..."
  "$GODOT_BIN" --headless --path "$ROOT" --script res://tools/test_3d_phase6.gd >"$LOG" 2>&1 || {
    tail -n 60 "$LOG"; echo "ERROR: 3D phase-6 test failed."; exit 1; }
  grep -E "3D PHASE-6 TEST:" "$LOG" || {
    tail -n 60 "$LOG"; echo "ERROR: 3D phase-6 test did not pass."; exit 1; }

  echo "[11/13] Running 3D touch regression (simulated Android drag + loop)..."
  "$GODOT_BIN" --headless --path "$ROOT" --script res://tools/test_3d_touch.gd >"$LOG" 2>&1 || {
    tail -n 60 "$LOG"; echo "ERROR: 3D touch regression failed."; exit 1; }
  grep -q "3D TOUCH TEST: all checks passed" "$LOG" || {
    tail -n 60 "$LOG"; echo "ERROR: 3D touch regression did not pass."; exit 1; }

  echo "[12/13] Running 3D benchmark (scenarios, leaks, draw discipline)..."
  "$GODOT_BIN" --headless --path "$ROOT" --script res://tools/benchmark_3d.gd >"$LOG" 2>&1 || {
    tail -n 60 "$LOG"; echo "ERROR: 3D benchmark failed."; exit 1; }
  grep -q "3D BENCH: all checks passed" "$LOG" || {
    tail -n 60 "$LOG"; echo "ERROR: 3D benchmark did not pass."; exit 1; }

  echo "[13/13] Running Android build host checks..."
  bash "$ROOT/tools/test_build_android_host.sh" || {
    echo "ERROR: Android build host checks failed."; exit 1; }
fi

echo "OK: project validated headless (import + $FRAMES frames + smoke + 3D phase-1, no errors)."
