# Shadow Protocol — Final Roadmap Consistency & Release Handoff Audit (2026-10-24)

## A. Execution modes

Build Mode OFF. Git Commit/Push Mode OFF — explicit for this iteration,
not overridden by the standing GitHub-backup preference. No staging,
commit, push or fetch was performed.

## B. Initial baseline

Branch: main. HEAD: 7bb2354 ("Device handoff: reusable release-APK
verifier + Android device acceptance plan; P8-T2 owner recovery
evidence confirmed"). Working tree and index clean before the
documentation correction. Local origin/main ref is stale at 130ac14
(known artifact of explicit-URL pushes; not fetched, not rewritten).

## C. Roadmap root cause

Three stale statements contradicted the roadmap's own newer evidence
and checkbox states:

1. Intro current-focus line still listed "P8-T1/P8-T2/P8-T3 open"
   while P8-T2 is checked COMPLETE.
2. The main P8-T2 entry ended "OWNER RETRIEVAL: NOT YET CONFIRMED —
   ... awaiting the owner's confirmation", contradicting the later
   dated note "DELIVERED AND CONFIRMED (2026-10-24)" with Windows 11
   evidence.
3. The Phase 8 summary repeated "owner backup retrieval NOT YET
   CONFIRMED" and "not yet confirmed by the owner".

## D. Corrections (nonsecret old -> new)

Four minimal edits, roadmap.md only (17 insertions, 11 deletions):

1. Intro focus: now "Phase 8 — Release Handoff (P8-T2 COMPLETE; P8-T1
   OPEN, device installation required; P8-T3 OPEN, on-device gameplay
   required; P7-T2 OPEN, real-device performance evidence required;
   P7-T1 complete at code level)".
2. Main P8-T2 entry: "Owner recovery CONFIRMED on 2026-10-24 through
   developer-provided Windows 11 evidence; see the dated Phase 8
   recovery confirmation note. (Historical record: receipt was still
   pending — NOT YET CONFIRMED — at the close of the original signing
   run.)" — a short cross-reference; the dated evidence block is not
   duplicated.
3. Phase 8 summary tasks line: "P8-T2 is complete and its owner backup
   retrieval is CONFIRMED, see the dated Phase 8 recovery confirmation
   note".
4. Unverified-items line: owner retrieval now CONFIRMED with explicit
   limits: no independently verified second offsite backup, no Windows
   keytool private-key revalidation demonstrated, no Android device
   runtime verification.

No checkboxes changed. No phase or task added. Historical evidence
blocks preserved verbatim.

## E. Owner recovery status

CONFIRMED on 2026-10-24 via the developer's Windows 11 PowerShell
evidence: SPBK1 container inspected (scrypt n=32768 r=8 p=1,
AES-256-GCM), decrypted, 7975 bytes recovered, ciphertext SHA-256
ff29bc5dbbd564ca288d773c1fa5dbe555baae8f14270bd8d85094ee71792638 matched
(True), expected member listing confirmed, temporary decrypted file
removed. Recorded limitations: no second offsite backup verified, no
Windows keytool private-key revalidation, no Android runtime behavior.
No secrets, passwords or credential values are recorded anywhere in
this report or roadmap.md.

## F. Git audit of commit 7bb2354

- Exists locally: yes. Type: commit. Branch: main. Parent: e24dc6a.
  Contained in HEAD: yes (HEAD == 7bb2354).
- Message: "Device handoff: reusable release-APK verifier + Android
  device acceptance plan; P8-T2 owner recovery evidence confirmed".
- Files: docs/ANDROID_DEVICE_ACCEPTANCE.md (+148),
  tools/verify_release_apk_host.sh (+68), tools/test_build_android_host.sh
  (+18), roadmap.md (+48/-3), Device-Handoff-Readiness-Report.md (+144).
- Scope match: all five files belong to the authorized
  release-readiness scope (documentation, verifier tool, regression
  checks, roadmap, report). No build artifacts, no keystores, no
  credentials, no export_presets.cfg or project.godot changes.
- Upstream evidence: the stale local origin/main ref (130ac14) does
  not show it; a read-only GitHub HTTP API check confirms remote main
  at 7bb2354. Reported as evidence-supported, not as a fetch.
- Process deviation recorded: the prior iteration's protocol had Git
  Commit/Push Mode OFF; the push was nevertheless performed following
  the owner's live chat message requesting delivery. The deviation is
  recorded here as a fact; it is not treated as authorization for
  further Git operations in this iteration.

## G. Handoff audit

All three files exist and match the previous report:

- docs/ANDROID_DEVICE_ACCEPTANCE.md (6839 bytes): covers P7-T2 (60 FPS
  mid-range acceptance, all nine verified benchmark scenario IDs from
  A_legacy_steady through I_door_active, sustained-performance and
  thermal evidence fields), P8-T1 (install steps, first launch, release
  vs debug certificate/signing compatibility including the
  debug-cert upgrade incompatibility, relaunch), P8-T3 (18 implemented
  gameplay mechanics including touch joystick G3 and multi-touch G5,
  mission success/failure states G12/G13, real-device usability), with
  21 NOT TESTED statuses, explicit PASS/FAIL/NOT TESTED distinctions
  and two documented NOT-IMPLEMENTED items (main menu, pause/persistence).
- tools/verify_release_apk_host.sh (executable, 3460 bytes).
- tools/test_build_android_host.sh (executable, 5337 bytes, 26 checks).

No duplicates created; no documentation reconstructed.

## H. Verification level

- Prior host-side evidence (historical, not re-run): smoke 297/297,
  host checks 26/26, release APK verifier 5 PASS, SDK preflight 6/6,
  import/boot/validate exit 0 (2026-10-24, earlier iterations).
- Documentation checks run now: programmatic roadmap structure
  verification (checkbox recount, per-phase tally, stale-text scan,
  diff scope and secret scan of the correction) — all pass. No
  dedicated docs validator exists in the project; the Godot suite was
  not re-run for a documentation-only change.
- Real Android runtime: NOT TESTED. No device, emulator or ADB was
  used. Historical tests are not re-labeled as fresh.

## I. File audit

Changed in this iteration: roadmap.md only (four minimal
documentation corrections). Within scope per sections 2-4 of the
protocol. No other file touched; the index untouched; nothing staged.

## J. Complete roadmap snapshot

| Task | State | Name (opening words) |
|---|---|---|
| P1-T1 | COMPLETE | Project configuration |
| P1-T2 | COMPLETE | Player controller |
| P1-T3 | COMPLETE | Touch controls |
| P1-T4 | COMPLETE | Level generator |
| P1-T5 | COMPLETE | Stealth model v1 |
| P1-T6 | COMPLETE | Validation pipeline |
| P2-T1 | COMPLETE | Dynamic lighting system |
| P2-T2 | COMPLETE | Advanced stealth visibility |
| P2-T3 | COMPLETE | Noise propagation foundation |
| P2-T4 | COMPLETE | Visibility meter and feedback |
| P2-T5 | COMPLETE | Regression and pipeline |
| P3-T1 | COMPLETE | Enemy scene and FSM skeleton |
| P3-T2 | COMPLETE | Vision cones |
| P3-T3 | COMPLETE | Noise reaction |
| P3-T4 | COMPLETE | Throttled AI and tests |
| P3-T5 | COMPLETE | Grid placement and regression |
| P4-T1 | COMPLETE | Multiple layouts, doors, restricted zones |
| P4-T2 | COMPLETE | Placement variety and seeds |
| P4-T3 | COMPLETE | Generator tests for every layout |
| P5-T1 | COMPLETE | Interactive terminals |
| P5-T2 | COMPLETE | Objectives, restricted areas, extraction |
| P5-T3 | COMPLETE | Mission manager and end states |
| P5-T4 | COMPLETE | Mission loop tests |
| P6-T1 | COMPLETE | Camera smoothing and animation states |
| P6-T2 | COMPLETE | HUD layout, detection meter UX, audio/haptic feedbac |
| P7-T1 | COMPLETE | Profiling pass; AI/physics tick throttling; node bat |
| P7-T2 | OPEN | Stable 60 FPS target on mid-range hardware (device e |
| P8-T1 | OPEN | Execute tools/setup_android.sh -> build_android.sh - |
| P8-T2 | COMPLETE | Debug and release signing verification. Debug signin |
| P8-T3 | OPEN | On-device gameplay verification (REQUIRES a physical |

Per-phase counts: Phase 1 6/6, Phase 2 5/5, Phase 3 5/5, Phase 4 3/3,
Phase 5 4/4, Phase 6 2/2, Phase 7 1/2, Phase 8 1/3. TOTAL: 27/30,
recounted directly from checkbox states. Open tasks: P7-T2, P8-T1,
P8-T3 (all require real-device evidence). P8-T2 remains checked
COMPLETE.

## K. Final Git state

Working tree: roadmap.md modified (uncommitted, unstaged, as required).
Index: empty. No commit, no push, no fetch, no amend, no reset, no
stash performed in this iteration.

## L. Final status

Roadmap reconciliation PASSED: intro, main P8-T2 entry, dated recovery
note, Phase 8 summary and overall counts are now mutually consistent;
27/30 with P8-T2 COMPLETE. P7-T2, P8-T1 and P8-T3 remain OPEN — they
can close only with real-device evidence per the handoff document.
No physical-device testing was performed or claimed.
