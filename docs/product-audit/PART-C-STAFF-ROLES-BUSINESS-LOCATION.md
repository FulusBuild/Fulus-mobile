# Part C — Staff, Roles, Business, and Location

**Status:** Source review and focused automated checks complete; physical-device and authenticated production behavior remain open
**Audit date:** 2026-11-19
**Repository:** `codex/fix-debug-signing-guard`, baseline `590295f7ad02d55fd2b84ac588cb88ddd2a39a9b`
**Working-tree note:** Existing Android build, SDK, and generated-code changes were preserved. This part also corrected one timezone-dependent assertion in `test/repository/employee_repository_sync_test.dart`.

## Scope and evidence

Reviewed employee roster/detail/deactivated flows, invitation creation and claim, permission delegation, staff status/role changes, location membership, active-location switching, business selection and local binding, employee access refresh/revocation, cross-device employee restore, location ownership review, relevant route gates, Supabase Edge Functions, migrations, RLS policies/grants, and focused tests.

The source trace covered the mobile UI/repositories and `FulusConnectionState`, `EmployeeCloudSessionCoordinator`, and `CloudSessionBootstrapCoordinator`; `fulus-staff-api`, `fulus-api`, and restore contracts; and the migrations for staff delegation, employee location authorization, inactive employee claim, location-scoped restore, ownership review, transaction business boundaries, and retention watermarks.

## Findings

### No new product/security defect observed in the reviewed source and test scope

The inspected boundaries are implemented as follows:

- Staff actions resolve the active membership from the authenticated Supabase user. Manager delegation is limited to an explicit action set, and `list_devices` remains owner/admin-only.
- Permission delegation is bounded by the actor's own permissions; managers cannot self-edit, grant permissions they do not hold, or manage role definitions. The server-side RPC remains authoritative if a client UI is bypassed.
- Invite inspection/account preparation uses the invitation token as a bearer credential; claim uses the authenticated user and server-side claim RPC. Claim recovery checks the claimed user and invitation email before returning access projection.
- Employee restore validates the snapshot business ID and projects only the employee's authorized location scope. The SQL regression fixture asserts that an unassigned location's operational data is omitted.
- The local database carries a durable single-business binding. Switching to another business uses authoritative recovery before exposing that business to local state; recovery refuses to replace data while queued writes or unresolved conflicts remain.
- Location switching verifies a cached, non-deleted location and serializes competing switches. Employee identities cannot switch away from their assigned location.
- Employee roster reads are location-scoped while queued outbox work for other locations can still drain. Server authorization remains responsible for mutations and sync filtering.

These are source and automated-test conclusions, not physical-device or end-to-end proof.

### C-001 — Timezone-dependent test assertion (fixed)

**Severity:** Test reliability; no product defect observed.
**Evidence:** The employee reconciliation test compared a locally reconstructed Drift `DateTime` directly to `DateTime(2026, 9, 30, 12)`. In the Pacific environment the value was `05:00`, representing the same instant as `12:00Z`, so the assertion failed despite correct persisted time.
**Change:** Compare with `isAtSameMomentAs(DateTime.utc(...))`.
**Verification:** The complete focused Part C suite passed after the change.

## Supabase production observations (read-only)

Project `bejcuvoxemwomcatgyxz` was inspected through schema metadata only; no business records were selected or changed.

- Deployed migrations include staff delegation, location-scoped employee restore, location ownership review resolution, business-boundary guards, and retention-watermark tracking through `20261011030000_index_location_foreign_keys`.
- The reviewed staff/location tables have RLS enabled. Membership and business reads check `auth.uid()` or business membership; administrative writes check `is_business_admin`; role permission changes use `can_manage_role_permission`.
- `location_ownership_review` and `sync_change_retention_watermarks` have RLS enabled without client policies, and the live table grants observed for them were only to `service_role`.
- Several other tables have broad SQL grants including `anon`, but their RLS policies are defined for the `public` role and gate reads/writes on `auth.uid()`/business authorization. This audit did not find a bypass in the reviewed policies. Keep the RLS policies as the security boundary; least-privilege grants remain a reasonable hardening follow-up.
- Supabase Security Advisor reports two INFO notices for the service-only no-policy tables above and a WARN that leaked-password protection is disabled. The Auth warning is cross-cutting with Part B and should be decided for the product's sign-in policy.

Production behavior was not exercised with an authenticated staff account. The SQL authorization and restore scripts in `supabase/tests/` are local-only, transactional fixtures; they were inspected but not executed against production.

## Automated verification

Command (Flutter 3.44.9, Windows host; command-scoped Git `safe.directory`, no global setting changed):

```powershell
flutter test test/repository/permission_repository_test.dart test/repository/employee_repository_sync_test.dart test/repository/location_repository_test.dart test/data/remote/fulus_staff_access_api_test.dart test/remote/cross_device_employee_restore_test.dart test/unit/switch_active_location_test.dart test/unit/active_location_resolver_test.dart test/app/active_location_provider_test.dart test/sync/location_sync_handler_test.dart test/sync/fulus_location_canonical_reconciler_test.dart test/sync/fulus_employee_canonical_reconciler_test.dart
```

Additional state/restore safety checks:

```powershell
flutter test test/remote/fulus_connection_state_test.dart test/remote/cloud_restore_coordinator_test.dart
```

**Result:** 67 tests passed across the command above and `flutter test test/remote/fulus_connection_state_test.dart test/remote/cloud_restore_coordinator_test.dart`; no skips or failures; approximately 18 seconds total. Tests cover permission ceilings/self-edit, missing-session failure, location-scoped roster reads, employee identity reconciliation, location repository behavior, staff API request contracts, scoped restore, active-location selection, business-selection/readiness state, restore safety gates, and location/employee sync reconciliation.

## Remaining verification gaps

- No physical-device walkthrough was run for invitation sharing/claiming, permission editing, staff deactivation/reactivation, role changes, location switching, or employee revocation. Capture screenshots and redacted logs with device/API/build details when the Android phone is connected.
- No authenticated production or QA manager/owner/employee action was exercised. Use a dedicated QA business and synthetic identities before testing mutations; do not create invitations or change access on the real business account.
- The SQL regression scripts were reviewed but not run against a local Supabase stack. There is no dedicated executable Deno/Edge Function authorization harness in this repository, so the complete action matrix currently relies on source review, RPC SQL tests, and API contract tests.
- Offline/restart/reconnect and concurrent role/location changes remain unverified on device.
- This is not release readiness evidence for broad deployment or millions of users.

## Documentation disposition and next work

`docs/deep-code-audit/PART-03-EMPLOYEE-ACCESS.md` and `PART-04-BUSINESS-LOCATION.md` remain historical evidence; their current source conclusions were rechecked here, but old branch-specific statuses were not rewritten. No document was removed. The next physical/backend session should verify invite → claim → restore, role/permission denial, revocation, and location isolation with QA identities, then continue to Part D.
