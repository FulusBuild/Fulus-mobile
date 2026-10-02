# Part 03 — Employee, Membership & Access Control

## Scope
Employees, invitations, memberships, roles, permissions, employee login/switching, permission projection, revocation, and business/location authorization.

## Baseline
- Baseline SHA: 4cfbdbfed16f6a7799fd2ee454c604e742a84b7f
- Audit branch: audit/deep-code-part-03-employee-access

## Structural inventory
Inspected:
- Local employee repository, permission repository, auth/session projection.
- Employee cloud session coordinator and staff access API.
- Staff Edge Function.
- Employee/location authorization migrations and staff permission-delegation migrations.
- Auth/session restoration and local permission tests.
- Router/app-shell permission gates.
- Device registration/revocation authorization boundary.

## End-to-end traces
### Employee onboarding
Owner/manager → staff Edge Function → membership/role authorization → invite RPC → employee roster row → invitation → employee claim → cloud membership → restore snapshot → local user/employee/session/permission projection.

### Permission resolution
Cloud membership + role/override permissions → StaffClaim → identity projection → local users, employees, user_permissions, sessions → router/app-shell/repository permission checks.

### Revocation
Cloud membership status/employee state → device revocation/location membership cleanup → get_my_access failure → local employee/user deactivation → permission/session cleanup → connection/sync disable.

## Findings

### P03-001

Severity: Medium  
Status: Fixed; required CI green.

File: supabase/functions/fulus-staff-api/index.ts  
Function: staff action authorization / list_devices

Observed behavior:
The Edge Function authorizes a non-admin with employees.manage for the general staff-management action set. The list_devices action was implemented in the same function but was not included in the explicitly manager-delegable action set; nevertheless, the final switch was reachable because canManageEmployees was true. The action then queried every device in the business using the service-role client.

Expected invariant:
employees.manage authorizes employee roster/access management, not device inventory visibility. Device inventory is an administrator-only surface, consistent with the existing revoke_device RPC.

Root cause:
list_devices had no action-specific authorization check after the broad canManageEmployees gate.

Impact:
A manager granted employee-management permission could directly call the Edge Function and enumerate all registered devices for the business, exceeding the intended permission boundary.

Fix:
Added an explicit list_devices && !isAdmin rejection before the action switch. The smallest boundary-preserving change was used; no permission model redesign was introduced.

Regression test:
No existing executable Edge Function test harness was found in the repository. The fix is covered by source-level authorization proof plus the repository normal static/test CI. A dedicated Edge Function authorization harness remains a test-infrastructure opportunity.

Cross-check:
change_member_role and set_role_permission remain unreachable to managers because they are not in managerDelegableActions. revoke_device is independently protected by the database RPC as owner/admin-only. Invite creation, permission changes, status changes, and employee mutations have separate server-side checks, including location checks where applicable.

## Areas proven / partially proven

- Server authorization: membership is resolved from the authenticated Supabase user, not a caller-supplied actor identity.
- Permission delegation: managers cannot add/remove permissions they do not themselves hold.
- Self-modification: local and server paths reject manager self-permission changes.
- Owner protection: owner membership permissions cannot be changed through staff access.
- Manager/admin boundary: managers cannot create or modify administrator access through the hardened staff RPCs.
- Location boundary: employee invitation and employee mutation paths require location access where a location is supplied or already assigned.
- Revocation: membership status changes update employee activity, location membership, and registered-device state; local access refresh removes stale local session/permission state on authorization failure.
- Identity projection: cloud user_id, membership ID, employee ID, and local employee identity are kept as separate fields rather than assuming one namespace.

## Remaining uncertainty
- Device-level runtime verification for the new list_devices guard requires an authenticated manager and administrator against the deployed Edge Function.
- The repository has no dedicated Edge Function authorization test harness, so this part cannot yet provide automated behavioral coverage for every staff action.
- Broader business/location isolation is continued in Part 04; this part only cross-checked the employee/access boundary.

## Session handoff

Part: 03 — Employee, Membership & Access Control  
Baseline SHA: 4cfbdbfed16f6a7799fd2ee454c604e742a84b7f  
Audit branch: audit/deep-code-part-03-employee-access  
Current SHA: f0af66c12b125ae24d969d21f9babb79aec23bf8

### Completed
- Structural and end-to-end employee/access trace.
- Permission and membership server-boundary inspection.
- Employee revocation and identity projection cross-check.
- Device access gap identified and fixed.

### Findings
- P03-001 Medium — manager could enumerate business devices through list_devices.

### Fixed
- Added administrator-only guard for list_devices.

### Still open
- Live manager-vs-admin verification of deployed Edge Function behavior.

### Deferred
- Full business/location isolation belongs to Part 04.
- Dedicated Edge Function authorization test harness is an infrastructure opportunity.

### Evidence
- Source inspection of Dart repositories, coordinator, Edge Function, and relevant SQL migrations.

### Tests
- Existing permission repository tests reviewed.
- No dedicated Edge Function test harness exists.

### CI
- CI run 37006328840 green: migration lint, static analysis, Flutter tests, live sync contract, and multi-device convergence.

### Runtime/production verification
- Pending authenticated manager/admin runtime test against the deployed Edge Function.

### Files inspected
- lib/data/repositories/employee_repository_impl.dart
- lib/data/repositories/permission_repository_impl.dart
- lib/data/remote/employee_cloud_session_coordinator.dart
- lib/data/remote/fulus_staff_access_api.dart
- lib/data/remote/cross_device_employee_restore.dart
- lib/data/repositories/auth_repository_impl.dart
- lib/app/router.dart
- lib/app/app_shell.dart
- lib/features/more/employees/presentation/screens/employees_list_screen.dart
- supabase/functions/fulus-staff-api/index.ts
- supabase/migrations/20260929130000_harden_staff_permission_delegation.sql
- supabase/migrations/20260930160000_employee_location_authorization.sql
- supabase/migrations/20261002092000_align_staff_management_permissions.sql
- supabase/migrations/20261002093000_harden_claim_for_inactive_employee.sql
- test/repository/permission_repository_test.dart
- test/repository/employee_repository_sync_test.dart

### Next recommended step
Part 04 — Business & Location Isolation.
