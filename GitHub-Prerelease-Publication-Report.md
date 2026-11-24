# Shadow Protocol — GitHub Pre-Release Publication Report (2026-11-14)

## A. Execution modes

Build OFF (nothing rebuilt). Git Commit/Push OFF (no commits, no pushes). GitHub Release Publishing ON, per explicit owner authorization.

## B. Initial baseline

- roadmap.md: 8 phases, 30 task IDs, **27/30** complete; open: P7-T2, P8-T1, P8-T3 (unchanged).
- Git: branch `main`, HEAD `e55ac7e` ("docs: reconcile Phase 8 release handoff roadmap"), working tree clean except two pre-existing untracked report files (`Release-Test-Build-Report.md`, `Roadmap-Consistency-Audit-Report.md`), left untouched.
- **Repository identity change discovered:** the old path `ceyhunmammadov9599-tech/shadow-protocol` now returns HTTP 301 to the canonical repository **`jeyhunmammadov738-ops/shadow-protocol`** (GitHub repository ID 1430312316, same history, main at e55ac7e, public, push permission present). The release was published against the canonical repository ID, not the redirecting old path.

## C. Artifact verification (before publication)

- Path: `shadow-protocol/build/ShadowProtocol-v0.1.0-release.apk`
- Filename: `ShadowProtocol-v0.1.0-release.apk`
- Size: 26,710,546 bytes · mtime 2026-10-24 20:53 UTC (the previously verified fresh build; not rebuilt, not substituted, debug APK not used)
- **APK file SHA-256:** `aba40fe03ad8abad704518206e3be1afe4f51d0eabec98d2086c8c4dc7c18905`
- Package: `com.shadowprotocol.game` · versionName 0.1.0 · versionCode 1 · minSdk 24 · arm64-v8a
- **Signing certificate SHA-256:** `74ec3b4ec475f65517f0676b30d801f9fc557a5bb733dcabd70a5f016c574a0b` (normalized comparison MATCH)
- `tools/verify_release_apk_host.sh`: exit 0, 5/5 PASS (zip integrity, metadata, v2+v3, fingerprint, no debug cert)
- APK SHA-256 (file) and certificate SHA-256 (identity) are distinct values and were not confused.

## D. Release metadata

- Tag: `v0.1.0-android-test.1` (previously unoccupied; no tags or releases existed)
- Title: "Shadow Protocol v0.1.0 — Android Test Build 1"
- Type: **pre-release** (prerelease=true, draft=false)
- Target commit: `e55ac7e3ff046eaa2e1450a56113eddf45692fb5`
- Provenance note: the APK was built while HEAD was `7bb2354` with a docs-only working-tree delta (roadmap.md). Commit `e55ac7e` differs from that tree only in roadmap.md, which is not compiled into the binary. No stronger source-to-binary provenance is claimed.
- Release page: https://github.com/jeyhunmammadov738-ops/shadow-protocol/releases/tag/v0.1.0-android-test.1

## E. Assets

- `ShadowProtocol-v0.1.0-release.apk` — 26,710,546 bytes, state uploaded
- `ShadowProtocol-v0.1.0-release.apk.sha256` — checksum file (content: `aba40fe0…c18905  ShadowProtocol-v0.1.0-release.apk`)
- No debug APK, keystore, SPBK backup, passwords, or private credentials attached.

## F. Publication verification (independent)

- Release fetched via API: correct repo, tag, prerelease=true, target e55ac7e
- Asset downloaded via API: 26,710,546 bytes; **downloaded SHA-256 `aba40fe03ad8abad704518206e3be1afe4f51d0eabec98d2086c8c4dc7c18905` = local SHA-256** (exact match)
- Downloaded copy re-verified with `verify_release_apk_host.sh`: exit 0, 5/5 PASS
- Browser download endpoint present for both assets

## G. Windows 11 handoff (developer, not yet performed)

1. Open https://github.com/jeyhunmammadov738-ops/shadow-protocol/releases/tag/v0.1.0-android-test.1
2. Download `ShadowProtocol-v0.1.0-release.apk`
3. Save to a local folder
4. Verify checksum in PowerShell:
   `Get-FileHash .\ShadowProtocol-v0.1.0-release.apk -Algorithm SHA256`
   Expected hash: `ABA40FE03AD8ABAD704518206E3BE1AFE4F51D0EABEC98D2086C8C4DC7C18905`
5. Transfer to the Android phone when device testing is authorized

The developer has **not** downloaded the file and **no installation has occurred** — both remain unconfirmed.

## H. Signing compatibility warning

A debug-signed installation with package ID `com.shadowprotocol.game` may make Android reject this release-signed APK as an in-place update. Removing the debug build resolves it, but uninstalling an app also removes its local data.

## I. Roadmap and source protection

roadmap.md unchanged (no modification needed or made): 27/30, P7-T2/P8-T1/P8-T3 open. Publishing a test APK does not complete physical-device acceptance. No project source, configuration, version, or signing file was modified.

## J. Security

No tokens, passwords, keystores, or private paths were printed or placed in assets or notes. The GitHub token was used only from the environment. Repository visibility unchanged (public).

## K. Final status

- Pre-release publication: **COMPLETE and verified end-to-end** (asset download hash-identical, signature re-verified)
- Remaining external prerequisites: physical Android device (P7-T2, P8-T1, P8-T3), all still OPEN
- No Git commits or pushes were performed in this iteration
