import '../entities/auth_user.dart';

/// Architecture Section 6's login flow.
///
/// The owner-approval PIN system Section 6 ALSO specifies is
/// deliberately NOT part of this — it depends on a backend endpoint
/// that doesn't exist yet (GET /api/auth/business/{id}/approval-hashes
/// — Section 6's own named gap, confirmed still absent from
/// backend/app/routers/auth.py as of this checkpoint) and Phase 0's
/// exit criterion doesn't need it. Building a partial version now, with
/// no real endpoint to sync against, would be hollow rather than
/// honest — left for its own pass once that backend work exists.
abstract class AuthRepository {
  /// The currently authenticated user, or null if no session is active.
  /// A plain getter rather than a reactive stream/StateNotifier in this
  /// checkpoint — there is no login/session-aware screen built yet to
  /// consume one, and Architecture Section 4's "reactive by default"
  /// rule is about what's rendered on screen; inventing a stream shape
  /// now, before a real consumer exists to validate it against, risks
  /// designing the wrong interface. Revisit once Volume 3's actual
  /// login/session UI gets built.
  AuthUser? get currentUser;

  /// Attempts a silent refresh using the stored refresh token — called
  /// once at app launch (bootstrap.dart), before any UI is shown, per
  /// Architecture Section 6's "no login form, no blank splash screen"
  /// requirement for a returning user. Returns the restored user, or
  /// null if there was no stored refresh token, it's no longer valid, or
  /// the server couldn't be reached right now — see
  /// AuthRepositoryImpl.restoreSession's own comment on why those last
  /// two cases are handled differently even though both return null.
  Future<AuthUser?> restoreSession();

  Future<AuthUser> login({required String username, required String password});

  /// Clears the local session — access token, stored refresh token, and
  /// currentUser. Also makes a best-effort call to the backend's own
  /// /api/auth/logout (an audit-log entry only; JWTs are stateless, so
  /// there's nothing server-side to invalidate) — see
  /// AuthRepositoryImpl's own comment on why that call's success is
  /// never a precondition for the local logout completing.
  Future<void> logout();
}
