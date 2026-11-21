# Fulus UX/UI follow-up handoff

This handoff is for another Codex session continuing the physical-device UX/UI work. Read it together with [`QA_MASTER_PLAN.md`](../QA_MASTER_PLAN.md) and [`PHYSICAL-DEVICE-UX-UI-AUDIT-2026-11-20.md`](PHYSICAL-DEVICE-UX-UI-AUDIT-2026-11-20.md).

## Repository state

- Repository: `FulusBuild/Fulus-mobile`.
- Current local checkout: `C:\Users\Sanni\Documents\Codex\fulus-part-mn-audit`.
- Current branch: `codex/recording-ux-followup`, based on `main` at merge commit `ce77e3c062c3c18376d42502863223b99188b533` (PR #238).
- PR #238, “Fix physical device UX audit findings,” is merged. Its CI passed analysis, Flutter tests, live sync contract, and multi-device convergence; APK jobs were skipped.
- PR #240, “Clarify onboarding for restored businesses,” is open at the original local base head `d3a12dfe`. Its recorded Fulus Mobile CI run 5108 and Vercel status succeeded for that commit. The new 2026-11-21 working-tree changes are not included in those remote checks.
- The follow-up onboarding copy and report updates in this checkout are not committed or pushed yet. Review `git status` first.
- Preserve the preexisting untracked `android/app/src/main/java/` and `android/local.properties`. Local build-runner `.g.dart` outputs are generated artifacts and should not be committed.

## User goal and workflow

The user wants a thorough UX/UI review of Fulus, including onboarding and real flows, with evidence-based source fixes. They have a way to build APKs and do not need Codex to build one. The phone was previously unavailable to ADB, so do not claim an updated-build device verification. The user has used a real business account; do not perform real-business mutations or reproduce recorded write flows against production.

## Recordings reviewed

- Local file: `C:\Users\Sanni\Downloads\Screenrecording_20261121_060259.mp4`.
- Duration: 364 seconds; the full visual timeline was reviewed using one locally extracted frame per second (365 frames). No audio was transcribed.
- Local file: `C:\Users\Sanni\Downloads\Screenrecording_20261121_065918.mp4`.
- Duration: 13 minutes 13 seconds; the full visual timeline was reviewed. Findings and source responses are recorded in `PHYSICAL-DEVICE-UX-UI-AUDIT-2026-11-20.md`.
- Temporary frame/contact-sheet output is under `%TEMP%\fulus_screenrecording_full_timeline`; these images contain business UI and must not be copied into the repository or shared separately.
- The APK version in the recording is unknown. The user operated the app; Codex made no business-data writes.

## Findings and current follow-up

1. **Misleading onboarding for a restored business:** the recording showed an existing catalog and sales history, but onboarding still said “Add your first product,” “Make your first sale,” and “You've created your first product.” The current local follow-up changes this to neutral catalog setup and sale prompts that work for new and restored businesses. Widget tests are in `test/features/onboarding/catalog_onboarding_copy_test.dart`.
2. **Brief blank Reports body:** around recording timestamps 243–244 seconds, the Reports header remained while the body showed a blank state/center spinner, then content rendered. PR #238 contains a fix for a nested unbounded loading viewport, but the recording APK version is unknown. Recheck using a new APK built from current `main`; do not call this a confirmed regression without that check.
3. **Sync conflict failure:** the recording showed a failed “Use Cloud version” attempt. The conflict remained unresolved, the backup screen retained its attention state, the choices reappeared, and local-safety messaging was shown. This is not evidence that the conflict was falsely resolved. Test successful resolution only in an isolated QA business.
4. The video includes user-entered sale/payment, repayment, stock movement, and cash drawer close flows. Do not copy account, customer, or transaction values into source, docs, issues, or chat summaries. Ask the user to rotate the password entered during the earlier unmasked sign-in observation.

## Current follow-up changes

The working tree now includes report layout improvements; neutral completion copy and a true walkthrough skip; least-privilege Cashier defaults for new invitations; retry-safe local employee identity and clearer invite failure feedback; a cash-without-drawer warning and drawer-session-accurate close labels; conflict-dominant sync status; and stock movement canonical identity reconciliation by server movement ID and outbox operation ID. A Supabase migration carries the stock operation ID in change-feed entries. The 2026-11-21 follow-up adds owner logout to a data-preserving welcome screen, period-correct Home sales labels, visible operational notices, responsive role-filtered Home shortcuts, and a permission-aware Stock navigation tab. Existing employee grants are unchanged. Inspect `git status` and the full diff before staging.

## Verification already run on this follow-up

- Generated local code with Flutter 3.44.9's bundled Dart to support focused checks. Generated outputs and `pubspec.lock` changes are temporary and must not be committed.
- The 2026-11-21 focused Flutter run passed auth-route guard, Home sales labels, dashboard engine/notices/repository, onboarding copy, permission defaults, stock movement repository/sync, Reports loading, payment split, and sync status/notifier: **72 tests passed**. A latest auth/Home check passed **8 tests** (7 overlap the prior run). These runs used locally generated `.g.dart` files; those outputs have been removed and `pubspec.lock` restored.
- Final targeted `flutter analyze` on the app shell, router, auth entry, Home, settings logout, and focused tests reported no issues. `git diff --check` passed.
- ADB returned no attached devices on 2026-11-21. No fresh APK/device UX verification is claimed.
- Do not run APK builds. The user supplies that step.

## Next actions

1. Inspect the complete diff and status; preserve user Android files and omit generated files.
2. Commit/push the UX follow-up source, migration, tests, and audit/handoff docs on `codex/recording-ux-followup`; update PR #240 and report the new CI state. Do not merge unless the user asks.
3. Ask the user to install a fresh APK and reconnect the TECNO KI5k to ADB for the onboarding, four-card Home, stock-history, cash-close, Reports, large-text, and sync-status recheck.
4. Use a disposable QA business for conflict-resolution and staff-invite success-path testing. Keep production business data read-only.
