# Shadow Protocol — Release APK Test Build & Final Roadmap GitHub Backup Report (2026-10-24)

## A. Execution modes

Build Mode ON; Git Commit/Push Mode ON (this iteration explicitly
authorized both). Scope honored: no new signing key, no gameplay
changes, no version bump, no APK/keystore/secret committed.

## B. Initial audit (fresh evidence)

- Roadmap: 8 phases, 30 unique task IDs, 27/30 complete.
  Per-phase: 6/6, 5/5, 5/5, 3/3, 4/4, 2/2, 1/2, 1/3.
  Open: P7-T2, P8-T1, P8-T3 (all device-dependent).
- Git baseline: branch main, HEAD 7bb2354, clean index, exactly one
  tracked modification (roadmap.md, +17/-11) and one untracked report.
  Remote main verified at 7bb2354 via read-only GitHub HTTP API.
- All eight referenced project files present (project.godot,
  export_presets.cfg, 5 tools scripts, docs/ANDROID_DEVICE_ACCEPTANCE.md).

## C. Signing identity continuity (no regeneration)

- Original keystore present in the private signing directory (mode 600,
  outside the repository).
- keytool listing (password via env, not argv, never printed):
  alias = shadow_protocol_upload; certificate SHA-256 fingerprint
  74ec3b4ec475f65517f0676b30d801f9fc557a5bb733dcabd70a5f016c574a0b —
  exact match with the verified release identity.
- No second keystore generated; alias and certificate unchanged;
  no credential value exposed.

## D. Fresh release APK build

- Command: tools/build_android.sh with GODOT_BIN set and
  SHADOW_PROTOCOL_KEYSTORE / _USER / _PASSWORD supplied through the
  environment (Godot GODOT_ANDROID_KEYSTORE_RELEASE_* overrides;
  export_presets.cfg untouched, verified byte-identical policy).
- Godot export completed; artifact overwritten at the standard output
  path with mtime 2026-10-24 20:53:31 UTC (fresh build).
- Known limitation (unchanged from the prior iteration): the script's
  internal apksigner step reports exit 1 in this environment because
  java is not on the script's PATH; the export itself succeeded and the
  standalone verifier (which locates the JDK itself) provides the
  authoritative signature evidence.

## E. Fresh release APK verification (actual results)

tools/verify_release_apk_host.sh — 5 PASS / 0 FAIL, exit 0:

1. ZIP archive integrity (153 entries, no corruption).
2. Package/version metadata: com.shadowprotocol.game, versionName 0.1.0,
   versionCode 1, minSdk 24, arm64-v8a.
3. apksigner verification: v2 true, v3 true.
4. Release certificate SHA-256 matches
   74ec3b4ec475f65517f0676b30d801f9fc557a5bb733dcabd70a5f016c574a0b.
5. Debug certificate NOT used (no debug-key fallback).

Artifact record:

- Filename: build/ShadowProtocol-v0.1.0-release.apk
- Size: 26,710,546 bytes
- SHA-256: aba40fe03ad8abad704518206e3be1afe4f51d0eabec98d2086c8c4dc7c18905
- Delivery ZIP SHA-256 (f1e33726…): built but upload blocked (see F).

## F. Host regression results (fresh)

- Godot import: exit 0.
- Headless boot (180 frames): exit 0.
- Smoke suite: 297/297 PASS (SMOKE TEST: all checks passed), exit 0.
- Android host checks: 26/26 PASS, exit 0.
- tools/validate_project.sh: exit 0.
- Combined fresh checks: 323 (297 + 26), all passing.

## G. APK delivery status — BLOCKED (precise blocker)

- The delivery ZIP was built and hashed locally
  (build/ShadowProtocol-v0.1.0-release.zip, 26,481,878 bytes).
- Upload to the established developer-authorized delivery route failed
  with CREDIT_LIMIT_REACHED: Base44 integration/file-upload credits
  are exhausted for the current billing period (100/100 used).
- No third-party delivery channel was created or used (per scope).
- The verified artifact and its ZIP are preserved locally and remain
  ready for delivery as soon as upload credits reset or the plan is
  upgraded. No claim is made that the developer's Windows PC can
  already access the file.

## H. Git finalization (authorized)

- Gates verified: branch main; remote origin
  https://github.com/ceyhunmammadov9599-tech/shadow-protocol.git;
  remote main at 7bb2354 before push; staged set exactly
  { roadmap.md }; staged diff scanned for secrets (0 matches).
- Commit e55ac7e "docs: reconcile Phase 8 release handoff roadmap"
  pushed to origin main (no force, no history changes).
- Remote main verified at e55ac7e via read-only GitHub HTTP API.
- Working tree after push: clean except the untracked audit report
  from the previous (Git-OFF) iteration, left untouched by scope.

## I. Roadmap preservation

- Eight phases, thirty task IDs, 27/30 complete preserved.
- P8-T2 remains COMPLETE; P7-T2, P8-T1, P8-T3 remain OPEN.
- This release APK is a TEST artifact only: no device installation,
  no FPS claim, no gameplay verification is claimed.
- Signing-identity caution documented (also in
  docs/ANDROID_DEVICE_ACCEPTANCE.md): if a debug-signed build with the
  same package id is installed on the test phone, Android will reject
  the release-signed APK as an update. Uninstalling the debug build
  clears the conflict but removes the debug app's local data — the
  game currently stores no persistent user data, but the removal is
  the developer's decision, not automated.

## J. Final status

- Fresh release APK: built, correctly signed with the original
  identity, fully verified (5/5). Ready as the primary test artifact.
- Roadmap corrections: committed and pushed (e55ac7e). 27/30.
- Device criteria: still OPEN, require real-device evidence.
- APK delivery: blocked solely by exhausted Base44 upload credits;
  artifact preserved and verified locally.
