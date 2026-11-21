# Fulus physical-device UX/UI walkthrough

**Evidence date:** 2026-11-20 (America/Los_Angeles)
**Evidence layer:** `DEVICE` manual walkthrough
**Status:** Source fix pass implemented 2026-11-20; physical recheck on the updated build remains pending. This is not a release-readiness assessment.

## Baseline and limits

- Device: TECNO KI5k, Android 12 / API 31, 720 × 1612 px (360 × 806 dp), font scale 1.0.
- Installed app: `com.fulus.app`, version `0.1.0`. The installed APK's source SHA was not established; this report does not claim the tested binary matches the current checkout.
- Repository checkout inspected: `codex/part-mn-sync-restore`, commit `8799c6936a296ebc9c1f613a4478904d7434c8e4`.
- Pre-existing untracked files observed and preserved: `android/app/src/main/java/` and `android/local.properties`.
- Account: the user's existing business account. Initial exploration was read-only. Cloud restore was run after the user cleared app data and authorized sign-in; this restored that account's data to the phone.
- No business records were created or edited. A cart item was added and removed during checkout inspection. Empty forms were submitted only to observe validation. No sale, repayment, expense, inventory movement, invite, location, or settings change was saved.
- Screenshots were used for live inspection. No screenshot containing account data is retained in this report. A password appeared unmasked in the sign-in capture despite the eye-off icon; the user was advised to treat it as exposed and change it after testing. No credential value is reproduced here.
- No automated tests were run as part of this manual UX walkthrough. Source observations below are labeled separately from device evidence.

## Coverage

Physically opened and inspected: fresh-start entry, sign-in and cloud restore, Home, Sell/cart/payment setup, receipt history/detail, Stock and product detail/edit, stock-action forms, customer list/profile and repayment form, Money history and expense entry, Reports, More, employees, locations, settings, backup/sync, printer setup, Notifications, and Diagnostics.

The owner-account creation flow was not completed against the real business. Staff sign-in/join, camera/barcode permission, printer discovery/pairing/printing, report sharing/export, file import, backup creation/import, and all financial or inventory commits were not exercised. Offline/restart behavior and large-text/accessibility behavior were not systematically tested. Do not infer a pass for these paths.

## Findings

### UX-001 — Password is rendered in clear text while the field indicates hidden

- **Severity:** High; credential exposure risk.
- **Evidence:** `DEVICE`, physical sign-in screen. With the eye-off/hidden state shown, the typed password remained visible in plain text in the field and in a live screenshot.
- **Expected:** Hidden state masks every password character; toggling visibility is explicit and consistent with the icon and accessibility label.
- **Impact:** Nearby observers or screen captures can disclose credentials. The user was told to change the exposed password after testing.
- **Root cause:** Not established by this walkthrough; inspect the password field's `obscureText`, controller/widget rebuild behavior, and visibility toggle.
- **Follow-up:** Reproduce with a synthetic account on a fresh build. Verify hidden, shown, focus/rebuild, autofill, and screenshot behavior. Do not reuse or record real credentials.

### UX-002 — Cart content overflows and controls collide

- **Severity:** High for checkout usability.
- **Evidence:** `DEVICE`, Sell/cart on 360 dp wide display. A red Flutter `OVERFLOWED BY 40 PIXELS` indicator appeared; long product content overlapped quantity/price controls and discount text was clipped. Reproduced twice. The checkout bar also displayed “1 items.”
- **Expected:** Cart rows adapt to narrow screens and long names; monetary/quantity controls remain distinct; item count uses correct singular/plural grammar.
- **Impact:** Users can have difficulty identifying or changing the intended item/quantity and may see incomplete discount information.
- **Root cause:** Not confirmed; likely row constraints and count-label formatting, to verify in source.
- **Follow-up:** Fix responsive row layout and pluralization; verify long names, large text, multiple items, and smallest supported width on device.

### UX-003 — Reports route stays blank without feedback

- **Severity:** High; core reporting path appears unavailable.
- **Evidence:** `DEVICE`, Reports screen remained blank for more than seven seconds on two visits; only the title and share icon were visible. No loading, empty, or error state appeared.
- **Expected:** Render report content or a clear loading/empty/error state with a retry path.
- **Impact:** User cannot tell whether reports are loading, empty, or broken. Share was not pressed.
- **Root cause:** Not established. Diagnostics later contained rendering-library errors, but no causal link to this route was demonstrated.
- **Follow-up:** Reproduce on a clean synthetic business and inspect route/provider errors; test populated and empty report data plus retry.

### UX-004 — Backup screens give contradictory status

- **Severity:** High; user trust and recoverability.
- **Evidence:** `DEVICE`, Sync & backup stated “Everything is backed up / Nothing needs your attention”; Cloud health simultaneously showed “Last successful backup Not yet recorded” and automatic backup “Waiting for first backup.”
- **Expected:** A single, consistent status that distinguishes local data, queued sync, and verified cloud backup.
- **Impact:** User may believe recoverable cloud data exists when no successful backup is recorded.
- **Root cause:** Not established; inspect the status sources and precedence rules.
- **Follow-up:** Derive all displayed backup claims from one canonical state and test no-backup, in-progress, success, stale, and failure states.

### UX-005 — Repayment amount defaults to the full outstanding balance

- **Severity:** High; financial action default.
- **Evidence:** `DEVICE`, customer repayment form. Amount field opened prefilled with the full outstanding amount. The form was not saved.
- **Expected:** Make the amount choice deliberate and clearly communicate the remaining balance before confirmation; validate any default against the intended partial-payment workflow.
- **Impact:** A user intending to enter a partial repayment could accidentally submit full settlement.
- **Root cause:** Not established. This report does not claim accounting corruption.
- **Follow-up:** Confirm product intent with users; if default remains, add conspicuous full-settlement context and confirmation, and test partial/full/overpayment paths in a QA business.

### UX-006 — Low-stock filter count disagrees with visible rows

- **Severity:** Medium; inventory attention signal.
- **Evidence:** `DEVICE`, Stock showed a “1 low” chip; selecting it displayed three low/zero-stock rows, including two zero quantities and one item at its threshold.
- **Expected:** The badge count and filtered list use the same low-stock rule and dataset.
- **Impact:** User cannot rely on the count to understand how many products need attention.
- **Root cause:** Not established; threshold inclusion and count semantics need source/data validation.
- **Follow-up:** Define whether “low” means below or at/below threshold, then use one predicate for both count and filter. Add boundary tests.

### UX-007 — Stock shortcuts split labels mid-word on narrow layout

- **Severity:** Medium; navigation clarity.
- **Evidence:** `DEVICE`, Stock at 360 dp. Shortcut labels “Movement” and “Categories” broke into fragments (“Moveme”/“nt” and “Categorie”/“s”).
- **Expected:** Labels wrap at word boundaries, use responsive sizing, or use accessible icons with readable labels.
- **Impact:** Shortcuts look broken and take longer to scan.
- **Follow-up:** Adjust constraints and verify at supported widths and larger text scale.

### UX-008 — Categories initially appears empty while loading

- **Severity:** Medium; loading feedback.
- **Evidence:** `DEVICE`, Categories was blank for about three seconds, then loaded a long list; no loading indicator was visible during the blank interval.
- **Expected:** Show progress or a deliberate empty state, then populated content or actionable error.
- **Impact:** Users may interpret a transient load as missing data.
- **Follow-up:** Verify slow/offline/error states and render explicit loading/empty/error UI.

### UX-009 — Custom date filter is clipped without a scroll cue

- **Severity:** Low/Medium; filter discoverability.
- **Evidence:** `DEVICE`, Money screen date-range chips: the Custom option was clipped at the right edge until horizontal swiping; no scroll cue was visible.
- **Expected:** Make horizontal overflow discoverable or fit/reflow the choices.
- **Impact:** Users may not discover custom date filtering.
- **Follow-up:** Test narrow width, larger text, and keyboard/accessibility navigation.

### UX-010 — Long customer names crowd the balance column

- **Severity:** Medium; customer list readability.
- **Evidence:** `DEVICE`, customer list with existing business data. Long names/identifiers wrapped across several lines and crowded the outstanding-balance column. Sensitive values are intentionally omitted.
- **Expected:** Keep identity and balance visually distinct with robust truncation/line limits and access to the full name on profile.
- **Impact:** Harder to scan customers and compare balances without opening profiles.
- **Follow-up:** Validate with long synthetic names, large text, right-to-left text if supported, and screen readers.

### UX-011 — Expense category choices are clipped on the form

- **Severity:** Low/Medium; input discoverability.
- **Evidence:** `DEVICE`, Add expense form showed horizontally clipped category choices (including a partially visible option) without a clear affordance. Empty submit produced validation feedback and no record was saved.
- **Expected:** Clearly indicate horizontal scrolling or present a layout that exposes available categories.
- **Impact:** Users may miss valid categories.
- **Follow-up:** Verify scroll affordance and keyboard/screen-reader access; test long category lists.

### UX-012 — Diagnostics reports rendering errors without useful attribution

- **Severity:** Medium; supportability.
- **Evidence:** `DEVICE`, Diagnostics showed repeated “Display error · rendering library” entries (23 errors at the observed moment) with a `RenderViewport ... was not laid out` detail, screen `—`, component “rendering library,” and confidence “UNKNOWN.” Count may include errors from this walkthrough; pre-existing status is unknown.
- **Expected:** Attribute errors to route/component and provide reproducible, actionable context without exposing private business data.
- **Impact:** Support and engineering cannot reliably connect a displayed error to its source.
- **Follow-up:** Reproduce using clean navigation and correlate app logs/Flutter error hooks to specific routes. Do not treat this count as proof of a pre-existing production incident.

## Source observation (not physical proof)

In checkout `8799c6936a296ebc9c1f613a4478904d7434c8e4`, router entries named `moneySuppliers` and `moneyDailyClosingCount` exist, but a repository-wide search found no `pushNamed` references for either route. This suggests the screens may be unreachable from current UI; confirm with generated route names, go_router redirects, deep links, and any indirect navigation before classifying as a defect. The Reports blank state is device evidence; its source cause is unresolved.

## Other observed UX notes

- Home dashboard, receipt history/detail, empty notifications, printer landing screen, and employee empty state were understandable in the inspected data state.
- Payment setup showed cash/transfer/card and split-payment controls; the sale was not completed.
- Stock-in, stock-out, and adjustment forms were distinct; no quantities were submitted.
- CSV import explained required/optional headers and disabled review until input was provided; no import was run.
- Employee invitation, location creation/switching, settings changes, receipt printing/sharing, and data exports were not submitted.
- During rapid navigation the app returned to Android Home once while Fulus remained running. It was foregrounded again; this was not confirmed as a crash and should not be filed as one.

## Remaining verification

1. Install the fixed APK on the TECNO KI5k after reconnecting it to ADB; record the APK SHA and repeat the affected screens and a larger text scale.
2. Capture sanitized screenshot evidence on a QA account/build before closing the device findings.
3. Use a synthetic QA business for creation, invitations, imports, backup creation/restore, and saved financial or inventory scenarios.
4. Reconcile this UX report with Parts A–P without changing their evidence layer or claiming end-to-end coverage from screen visits.

## Fix pass — 2026-11-20

The following source changes and focused regression checks were made after the device observations. They have not yet been rechecked on a newly installed APK because no Android device was attached to ADB at fix time.

| Finding | Source change | Verification status |
|---|---|---|
| UX-001 | Obscured `FulusTextField`s now set an explicit bullet mask and disable autocorrect and suggestions. The sign-in screen already passed `obscureText`; the original device binary's mismatch cannot be explained from this checkout alone. | Widget test passes for masking configuration; fresh-build device check and password rotation remain outstanding. |
| UX-002 | Cart line items now stack details, total, discount, and quantity controls on narrow cards. The Sell bar uses singular/plural item wording. | Analyzer passes; physical long-name/discount layout check remains outstanding. |
| UX-003 | Report loading no longer inserts a nested unbounded `ListView` into the Reports page's outer `ListView`. The retained-data refresh state no longer uses `Expanded` under unbounded vertical constraints. | Dedicated nested-scroll loading widget test passes; populated/empty/error/refresh behavior on-device remains outstanding. |
| UX-004 | Settled sync with no successful outbound timestamp now says “Waiting for first backup” and explains that only local data is confirmed. | Sync-status regression test passes; device state check remains outstanding. |
| UX-005 | Repayment amount starts blank; the outstanding balance is shown separately beside the amount field. | Widget test passes; full/partial/excess repayment behavior was not written to the real business and needs isolated QA verification. |
| UX-006 | The low-stock count now uses the same `ProductWithStock.isLowStock` predicate as the filter, including zero-stock and threshold-equal products. | Boundary regression test passes. |
| UX-007 | Stock shortcuts use two columns on narrow screens and three on wider screens, preventing labels from being squeezed into narrow thirds. | Analyzer passes; font-scale/device visual check remains outstanding. |
| UX-008 | Category loading now pairs the existing skeleton with a visible, screen-reader-announced progress indicator. | Analyzer passes; slow-network visual check remains outstanding. |
| UX-009 | Money period filters use wrapping layout instead of hidden horizontal overflow. | Analyzer passes; small-screen/date-selection check remains outstanding. |
| UX-010 | Customer names are limited to two lines and phone/subtitle to one line with ellipsis, keeping the balance column distinct. | Analyzer passes; long synthetic names and accessibility scale need device verification. |
| UX-011 | Expense category and payment options wrap into visible rows instead of clipping horizontally. | Analyzer passes; on-device form review remains outstanding. |
| UX-012 | Global layout diagnostics now prefer the relevant app widget or RenderObject from Flutter's error collector as the component name. Per-branch Navigator observers remember nested routes, and the shell selects the visible branch's screen for diagnostics after tab switches. | Three focused tests cover component parsing and active-branch attribution; generate a fresh layout error on-device and confirm the Diagnostics detail view. |

The source-only navigation observation was also resolved by adding Money screen entries for Suppliers and Daily cash close. No supplier, drawer, or financial record was created by these navigation changes.

Focused checks run with Flutter 3.44.9: `fulus_text_field_test.dart` (1 pass), `stock_filter_test.dart` (1 pass), `ledger_payment_screen_test.dart` (1 pass), `reports_loading_skeleton_test.dart` (1 pass), `global_error_capture_test.dart` (2 pass), `current_screen_tracker_test.dart` (1 pass), and `sync_status_test.dart` (3 pass), for 10 passing tests. Targeted `flutter analyze` across the changed app and test files reported no issues. Code generation ran locally to support tests; generated sources are not part of the intended change.

The physical phone was not attached when checking ADB after these changes (`adb devices -l` listed no devices). Therefore no updated APK install or device recheck is claimed. A local `flutter build apk --debug` was started but stopped before producing an APK when Gradle's Java process reached approximately 1.5 GB and stalled without visible progress. The repository's existing GitHub Actions `debug_apk` job can build an artifact from a pushed branch via manual workflow dispatch. Change the password that was captured unmasked during the original walkthrough; the app cannot rotate that credential for the user.

## Full screen-recording follow-up

The user-provided `Screenrecording_20261121_060259.mp4` is 364 seconds long. The full timeline was reviewed from one locally extracted frame per second (365 frames); no audio was transcribed. The APK commit/version in the recording cannot be identified.

- The restored business already contains products and sales, but the first-run walkthrough still called the next steps “Add your first product” and “Make your first sale,” and stated “You've created your first product.” This is inaccurate for a returning/restored business. The follow-up source change replaces those claims with catalog and sale prompts that work for both new and existing businesses; focused widget coverage is added.
- Reports displays its page header with a blank body and centered spinner for about two seconds around recording timestamps 243–244, then renders report controls and data. PR #238 contains the source fix for a nested unbounded loading viewport, but the recording's APK version is unknown. Verify this flow again on a build from merged `main`; do not treat the clip as proof that the fix regressed.
- Sync conflict resolution was attempted and reported a refresh failure. The unresolved cash-drawer conflict remained visible and backup health continued to say attention was needed; the screen offered both resolution choices again and told the user local data remained safe. This is a retained conflict, not evidence of a false successful resolution. Recheck the success path on an isolated QA business.
- The recording includes user-submitted sale/payment, repayment, stock movement, and cash drawer close actions. The reviewing agent made no business-data writes. Sensitive account and transaction values are intentionally omitted from this report.

Both onboarding copy widget tests pass; all 12 focused tests pass after local code generation. The full recording raises no additional Reports source defect that can be distinguished from an APK-version mismatch; fresh-build device verification remains open.
