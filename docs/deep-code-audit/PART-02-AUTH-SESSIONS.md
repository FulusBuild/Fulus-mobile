# Part 02 — Authentication & Sessions

**Status:** Source audit complete; fixes implemented; CI/runtime verification pending.

## Scope

Authentication and session lifecycle across:
- local identity creation and restoration
- local identity switching and PIN authentication
- cloud email/password sign-in and signup
- email verification deep-link session capture
- Supabase refresh-token persistence and rotation
- cloud session restoration
- employee cloud-session establishment/readiness
- sign-out and cloud-session cleanup
- auth error mapping
- reactive session projection
- auth-related tests

## Baseline

**Baseline main SHA:** 42ea5339fe5ab4eb98fb9439879ecf52a8300360

**Audit branch:** audit/deep-code-part-02-auth-sessions

## Structural inventory

### Primary implementation
- lib/domain/repositories/auth_repository.dart
- lib/domain/entities/auth_user.dart
- lib/data/repositories/auth_repository_impl.dart
- lib/data/local/secure_storage/secure_storage.dart
- lib/data/remote/api_client.dart
- lib/data/remote/endpoints/auth_api.dart
- lib/data/remote/employee_cloud_session_coordinator.dart
- lib/data/remote/fulus_connection_state.dart
- lib/core/auth/email_verification_deep_link_handler.dart
- lib/app/bootstrap.dart
- lib/app/providers.dart
- lib/features/auth/presentation/screens/auth_gate_screen.dart
- lib/features/auth/presentation/screens/fulus_account_screen.dart
- lib/features/auth/presentation/screens/identity_picker_screen.dart
- lib/features/auth/presentation/screens/employee_login_screen.dart
- lib/features/auth/presentation/screens/employee_join_business_screen.dart
- lib/features/auth/presentation/screens/backup_restore_decision_screen.dart
- lib/features/auth/presentation/screens/cloud_restore_screen.dart
- lib/features/auth/presentation/screens/restore_progress_screen.dart
- lib/features/auth/presentation/screens/app_lock_screen.dart

### Tests inspected
- test/repository/auth_repository_test.dart
- test/data/remote/api_client_test.dart
- test/data/remote/auth_api_test.dart
- test/remote/fulus_connection_state_test.dart
- related auth/session call sites found by repository-wide code search

## Pass A — Structural inventory

The implementation contains two deliberate layers:

1. **Local identity/session**
   - Users table identity
   - singleton Sessions row
   - AuthRepositoryImpl
   - local PIN verification/lockout
   - sessionProvider projection

2. **Cloud authentication/session**
   - Supabase email/password sign-in and signup
   - SecureStorage refresh tokens
   - ApiClient auth interceptor
   - single-flight refresh
   - cloud user selection
   - FulusConnectionState
   - employee cloud-session coordinator

The critical boundary is that these two identity namespaces are not universally identical. Employee cloud projections currently use the Supabase user ID as the local identity ID; locally-created owner identities use a ULID.

## Pass B — Function/class audit

### AuthRepositoryImpl
Inspected:
- hasAnyOwnerAccount
- restoreSession
- createFirstOwner
- setOwnLoginPin
- listLocalIdentities
- switchLocalUser
- createAdditionalOwner
- createEmployeeAccount
- logout
- getAssignedLocationId
- getActiveLocationId
- setActiveLocationId
- _persistSession
- _clearSession
- _insertLocalIdentity
- PIN validation and lockout branches

Verified:
- session restore rejects missing/deactivated local users
- inactive identities cannot switch successfully
- PIN failures increment and lock after five failures
- successful switches reset failed-attempt state
- employee switches use roster-assigned location
- singleton local session is persisted transactionally
- local session persistence does not invent a PIN

### ApiClient / auth interceptor
Inspected:
- access-token attachment
- 401 handling
- retry-after-refresh path
- shared refresh single-flight
- startup server-session restoration
- per-user server-session restoration
- refresh-token rotation persistence
- refresh rejection handling
- active cloud-user projection
- auth error mapping

Verified:
- concurrent 401s share one refresh transaction
- startup restore shares an in-flight refresh
- transient refresh failure preserves the durable refresh token
- rejected refresh tokens expire the cloud session
- retried 401 cannot recurse indefinitely

### AuthApi
Inspected:
- connectServer
- signUpServer
- resendSignupVerification
- acceptEmailVerificationTokens
- createCloudBusiness
- registerCloudDevice
- restoreServerSession

### EmployeeCloudSessionCoordinator
Inspected:
- establish
- refreshExistingAccess
- activateExisting
- _upsertIdentityProjection
- location/employee resolution
- permission projection
- cloud access revocation path

### UI/session projection
Inspected:
- AuthGateScreen
- FulusAccountScreen
- IdentityPickerScreen
- EmployeeLoginScreen
- EmployeeJoinBusinessScreen
- Settings logout flow
- sessionProvider update points

## Pass C — Line/branch audit

### P02-001 — Cloud/local identity namespace mismatch

**Severity:** High  
**Status:** Closed in source scope; runtime/production verification pending.

**Observed behavior**

Bootstrap restored the local session, then assigned AuthRepository.currentUser.id directly as ApiClient's active cloud user. That is not a valid identity mapping for locally-created owners because the local user receives a ULID while Supabase Auth has a different user ID.

The refresh interceptor also previously fell back from a missing selected user's refresh token to the legacy global refresh token. With an explicitly selected cloud identity, this could bind another account's cloud credential to the current identity and persist the rotated credential under the wrong key.

Per-user restore also accepted a successful refresh response without verifying that Supabase returned the requested cloud user ID.

**Expected invariant**

The local authenticated identity and cloud authenticated identity must never be silently conflated. A refresh credential selected for one cloud user must never be used as another selected cloud user's credential.

**Fix**

- Removed bootstrap's local-ID-to-cloud-ID assignment.
- Startup/global refresh now binds the active cloud identity from the Supabase refresh response.
- Explicitly selected cloud users only use their own per-user refresh token.
- Per-user refresh rejects a response for a different cloud user.
- Added regression tests for all three boundaries.

**Regression evidence**

Added to test/data/remote/api_client_test.dart:
- startup restore establishes the returned cloud user ID;
- selected cloud identity never falls back to the global token;
- per-user refresh rejects a mismatched cloud identity.

### P02-002 — Auth transition coupled to audit persistence

**Severity:** Medium  
**Status:** Closed in source scope; runtime/production verification pending.

**Observed behavior**

AuthRepositoryImpl committed session state before writing the local AUTH audit entry. If audit persistence threw, callers could observe an authentication method throwing after the session had already changed. Logout was particularly unsafe because a thrown audit write could prevent the caller from continuing to clear cloud/session projections.

**Expected invariant**

An already-committed authentication transition must not be reported as failed because secondary audit persistence failed.

**Fix**

Added _logAudit(), making auth audit writes best-effort after the auth state transition is committed.

**Regression evidence**

Added to test/repository/auth_repository_test.dart:
- successful local identity switch remains committed when audit persistence throws;
- logout remains committed when audit persistence throws.

## Pass D — Cross-system audit

### Fresh owner account

Email/password cloud authentication creates/restores the Supabase session first. Local owner identity/business provisioning then occurs, and cloud business/device setup follows. On restart, local session restoration is independent from cloud session restoration.

The important identity boundary is now:
local session → durable cloud refresh credential → Supabase refresh response → authoritative cloud user ID.

### Employee authentication

Employee email/password login establishes the Supabase session, resolves active membership, obtains StaffClaim, restores the business snapshot, projects the cloud employee identity locally, registers the device, enables sync, and only then exposes the restored local employee session.

### Local employee switching

IdentityPicker first validates the local PIN, then for employee identities restores that employee's cloud session and validates the returned membership claim before activating sync readiness. Failure cleanup clears the partial employee session.

### Sign-out

Settings logout commits local logout, clears the active cloud session, disconnects connection state, disables sync, and clears the reactive session provider. Per-user employee refresh credentials remain available intentionally so the shared-device identity picker can restore a previously provisioned employee without re-provisioning the account.

### Email verification

The deep-link handler accepts access/refresh tokens into the cloud client. The subsequent normal cloud initialization now derives the cloud identity from the Supabase refresh response rather than from the local Users ID.

## Failure paths considered

- fresh install
- warm restart
- process death after local session commit
- process death after cloud sign-in
- offline/transient refresh failure
- explicit refresh-token rejection
- concurrent 401 refresh
- concurrent startup restore + 401
- wrong PIN
- PIN lockout
- deactivated local identity
- revoked employee cloud access
- failed employee cloud switch
- audit persistence failure
- mismatched cloud identity response
- missing selected-user refresh credential
- legacy/global refresh credential

## Remaining uncertainty / deferred evidence

1. Android runtime evidence is still required for fresh-install owner sign-in, kill/reopen, refresh-token rotation, and process-death boundaries.
2. Shared-device employee A/B switching should be reproduced with a real Supabase session for both employees, including process death between switching and sync.
3. Production Supabase evidence should verify the refresh response identity and the current account/session configuration.
4. Restore-vs-active-sync remains cross-cutting finding X-001 from Part 01 and belongs to Parts 15/17.
5. Full authorization implications of employee membership/permission changes continue in Part 03.

## Definition-of-done checklist

- [x] File inventory completed
- [x] Classes/interfaces inspected
- [x] Functions/methods inspected
- [x] Important branches inspected
- [x] Call chains traced
- [x] DB boundaries inspected
- [x] Network boundaries inspected
- [x] Authorization boundaries considered
- [x] Concurrency/retry behavior considered
- [x] Failure paths considered
- [x] Tests reviewed
- [x] Missing tests identified
- [x] Concrete findings recorded
- [x] Fixes implemented where justified
- [x] Regression tests added
- [ ] Relevant tests pass in this session
- [ ] Required CI passes
- [x] Cross-check completed
- [x] Evidence recorded
- [x] Remaining uncertainty documented
- [x] Part document created

## Session handoff

**Part:** 02 — Authentication & Sessions  
**Baseline SHA:** 42ea5339fe5ab4eb98fb9439879ecf52a8300360  
**Audit branch:** audit/deep-code-part-02-auth-sessions  
**Current SHA:** 29075b2ab8cc0defc7b6bde141ac2a62514cfb4d

### Completed
- Deep source audit of local and cloud authentication/session paths.
- Identified and fixed cloud/local identity namespace confusion.
- Hardened selected-user refresh so it cannot fall back to another/global credential.
- Added response-identity validation.
- Made auth transitions independent of audit-write failures.
- Updated findings and cross-cutting ledger.

### Findings
- P02-001 High — cloud/local identity mismatch and credential fallback.
- P02-002 Medium — audit write could fail an already-committed auth transition.

### Fixed
- Both findings fixed in source and covered by regression tests.

### Still open
- Runtime/production evidence for startup refresh, shared-device employee switching, and process death.

### Deferred
- X-001 restore/sync maintenance race remains owned by Parts 15/17.
- Broader employee authorization remains Part 03.

### Evidence
- Source trace across auth repository, ApiClient, AuthApi, employee coordinator, bootstrap, auth screens, secure storage, and auth tests.
- Supabase documentation confirms refresh tokens are one-use/rotated and refresh responses identify the authenticated user.

### Tests
- test/repository/auth_repository_test.dart updated.
- test/data/remote/api_client_test.dart updated.
- Full test suite not yet run from this environment.

### CI
- Pending.

### Runtime/production verification
- Pending.

### Files inspected
- lib/app/bootstrap.dart
- lib/app/providers.dart
- lib/domain/repositories/auth_repository.dart
- lib/domain/entities/auth_user.dart
- lib/data/repositories/auth_repository_impl.dart
- lib/data/local/secure_storage/secure_storage.dart
- lib/data/remote/api_client.dart
- lib/data/remote/endpoints/auth_api.dart
- lib/data/remote/employee_cloud_session_coordinator.dart
- lib/data/remote/fulus_connection_state.dart
- lib/core/auth/email_verification_deep_link_handler.dart
- lib/core/onboarding/onboarding_routing.dart
- auth presentation screens listed above
- test/repository/auth_repository_test.dart
- test/data/remote/api_client_test.dart
- test/data/remote/auth_api_test.dart
- test/remote/fulus_connection_state_test.dart

### Next recommended step
Part 03 — Employee, Membership & Access Control
