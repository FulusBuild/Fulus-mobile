# Part B — Authentication and Sessions

**Status:** Source and focused automated audit complete; physical-device/backend flows remain open
**Audit date:** 2026-11-19
**Repository:** `codex/fix-debug-signing-guard`, baseline `c6843b0` (Part A commit); findings below were verified against the working tree after the noted fixes. The tree already contained unrelated Android/build/generated changes before this part; they were preserved.

## Scope

Reviewed local identity creation and switching, durable local session state, logout/restore, Supabase access-token refresh and per-user background refresh, employee login route handling, cloud connection state, and focused tests. Key source includes `lib/data/repositories/auth_repository_impl.dart`, `lib/data/remote/api_client.dart`, `lib/app/router.dart`, `lib/features/auth/presentation/employee_login_screen.dart`, and associated auth/session tests.

No production Supabase account or live business data was used or modified in this part. Automated HTTP behavior used test doubles; local persistence behavior used the repository's SQLite test database.

## Findings and fixes

### B-001 — Per-user token refresh did not bind the response to the requested identity

**Severity:** High (cross-identity session integrity)
**Evidence:** `AUTOMATED`, synthetic HTTP test. A refresh requested for `user-a` could return a successful session for `user-b`; the old code cached the foreign access token and associated its rotated refresh token with the requested user.
**Fix:** `ApiClient._refreshUserAccessToken` now validates the returned user ID before caching tokens or persisting refresh-token rotation. On mismatch it clears that user's scoped cached access token and returns null.
**Regression coverage:** `test/data/remote/api_client_test.dart` covers a mismatched response and a matching response with normal rotation.

### B-002 — In-memory local identity could move before the durable session transaction succeeded

**Severity:** Medium (session/UI state consistency)
**Evidence:** `AUTOMATED`, injected SQLite persistence failure. `createFirstOwner` could expose a signed-in user when its session row was not committed; `switchLocalUser` could expose the new user while the durable row still named the prior user.
**Fix:** Both operations now persist the session before updating `_currentUser`. A failed persistence operation leaves the in-memory identity unchanged.
**Regression coverage:** `test/repository/auth_repository_test.dart` covers both failure paths.

### B-003 — A signed-in user could enter employee login, whose failure cleanup clears the active session

**Severity:** Medium (unexpected logout / identity disruption)
**Evidence:** `SOURCE` trace from the `/login` route through `EmployeeLoginScreen` failure cleanup. A direct navigation to employee login while already signed in could reach cleanup that logs out the active local identity.
**Fix:** The router redirects an authenticated identity from `/login` to `/`; signed-out users can still access employee login. The pure guard is in `lib/core/auth/auth_route_guard.dart` and is applied by `lib/app/router.dart`.
**Regression coverage:** `test/core/auth/auth_route_guard_test.dart` covers signed-in redirect, other routes, and signed-out access.

## Verification

- `flutter test test/core/auth/auth_route_guard_test.dart test/data/remote/api_client_test.dart test/data/remote/auth_api_test.dart test/repository/auth_repository_test.dart test/remote/fulus_connection_state_test.dart` — passed, **53 tests**.
- `flutter analyze lib/app/router.dart lib/core/auth/auth_route_guard.dart lib/data/remote/api_client.dart lib/data/repositories/auth_repository_impl.dart test/core/auth/auth_route_guard_test.dart test/data/remote/api_client_test.dart test/repository/auth_repository_test.dart` — passed, **no issues** (61.4 seconds).
- Flutter required a command-scoped `safe.directory` Git setting because its SDK checkout is owned by the normal Windows account while commands run under the sandbox identity. No global Git config was changed.

## Open evidence gaps

- No current physical-device authentication walkthrough was performed in this part. In particular: fresh sign-in, wrong credentials, recovery/OTP, offline login behavior, app force-stop/restart, refresh-token expiry/revocation, and switching local/cloud identities remain unverified on Android.
- No live Supabase auth flow was exercised, and no real account was modified.
- Earlier campaign evidence records the TECNO KI5k Android 12 debug app launch but loss of the ADB wireless connection. Reconnect before device testing and record the exact build and account role. Do not treat these automated tests as end-to-end verification.

## Documentation disposition

This report is the current Part B result. `docs/deep-code-audit/PART-02-AUTH-SESSIONS.md` remains historical source-audit evidence and must not be treated as a current verification result without revalidation. No document was removed.

## Next action

Continue with Part C (Staff, roles, business/location), retaining the device/backend gaps above for the final combined findings and runtime session.
