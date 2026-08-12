import '../entities/auth_user.dart';

/// Architecture Section 6's login flow, re-scoped by the Architecture
/// Redesign: local Business Engine, no server-issued credentials, no
/// client/server boundary for any of this anymore. Every method below
/// is now backed entirely by the local Users table (AuthRepositoryImpl)
/// — nothing here makes a network call.
///
/// The owner-approval PIN system is still deliberately NOT part of this
/// interface, for the same reason as before the redesign: it's a
/// separate concern with its own repository (ApprovalPinRepository) and
/// its own sync path, not something this login/session lifecycle needs
/// to own — and it remains a genuinely multi-device concern (one
/// device's owner approving something on a DIFFERENT device), unlike
/// everything in this interface, which is now single-device by design.
abstract class AuthRepository {
  /// The currently authenticated user, or null if no session is active.
  /// A plain getter rather than a reactive stream/StateNotifier, for the
  /// same reason as before this redesign — no login/session-aware
  /// screen built yet to consume one; revisit once Volume 3's actual
  /// onboarding/login UI gets built.
  AuthUser? get currentUser;

  /// Whether any local Owner account exists yet on this device. Answers
  /// the same question the backend's GET /api/auth/bootstrap-status
  /// used to (verified directly against routers/auth.py) — false means
  /// this is a genuinely fresh install and the UI should show
  /// "create your business" (Volume 3), not a login form; true means it
  /// should show sign-in instead. No server round-trip anymore: this is
  /// a plain local Users-table count.
  Future<bool> hasAnyOwnerAccount();

  /// Restores the active session at app launch (bootstrap.dart), before
  /// any UI is shown, per Architecture Section 6's "no login form, no
  /// blank splash screen" requirement for a returning user. Was: attempt
  /// a silent token refresh. Now: read which local user the Sessions
  /// table says is current, and return them — or null if there's no
  /// active session row, or the user it points to is no longer active
  /// (Volume 9's access-revocation case; see AuthFailure.sessionExpired's
  /// doc comment). Either way, null means "show sign-in," same as
  /// before, just for a different, purely local reason now.
  Future<AuthUser?> restoreSession();

  /// Creates the very first local Owner account and signs them in
  /// immediately — mirrors the backend's bootstrap_admin exactly
  /// (verified directly: the first account created is always Owner-
  /// equivalent regardless of what's requested), collapsed into one
  /// step rather than create-then-separately-log-in, since there's no
  /// remaining reason to force a redundant explicit login right after
  /// creating the device's first account. Must only be called when
  /// [hasAnyOwnerAccount] is false — AuthRepositoryImpl enforces this
  /// itself rather than trusting the caller to have checked.
  Future<AuthUser> createFirstOwner({
    required String username,
    required String email,
    required String fullName,
    required String password,
  });

  /// Logs an existing local account in — same signature as before this
  /// redesign; only what's underneath it changed (a local Users-table
  /// lookup + Argon2id verify + the ported lockout check, instead of a
  /// POST to the backend).
  Future<AuthUser> login({required String username, required String password});

  /// An already-signed-in Owner creates ANOTHER local Owner account on
  /// this same device — Volume 9, Decision 33's co-equal-owners-sharing-
  /// a-till case (e.g. two owners, one physical counter). Genuinely new:
  /// the backend had an equivalent (admin-gated create_user), but
  /// nothing in the mobile app called it before this stage.
  /// AuthRepositoryImpl enforces that [currentUser] is actually an Owner
  /// before allowing this — the local check IS the real enforcement now
  /// (see AuthFailure.forbidden's doc comment), not just UI convenience.
  Future<AuthUser> createAdditionalOwner({
    required String username,
    required String email,
    required String fullName,
    required String password,
  });

  /// Clears the local session. Was also a best-effort call to the
  /// backend's /api/auth/logout audit-log entry; gone along with the
  /// rest of the JWT-era plumbing — there's no remote session to record
  /// against anymore. AuthRepositoryImpl records a local LOGOUT audit
  /// entry directly instead (Stage 3: Audit Engine, since built) — no
  /// network round-trip needed for it to still happen reliably.
  Future<void> logout();

  /// An already-signed-in Owner sets up sign-in credentials for an
  /// existing roster entry (Employees, EmployeeRepository), so that
  /// person can subsequently log in on this same device with their own
  /// account rather than sharing the owner's. This is deliberately a
  /// same-device, owner-provisioned action — not a cross-device
  /// invite/QR-claim flow (Volume 9 describes one, but Employees is
  /// explicitly not a synced table in this architecture, so nothing
  /// about a roster entry is visible to a second device to claim
  /// against; a cross-device version is a later-phase capability once
  /// Employees has a sync story, not a Phase 0 one).
  ///
  /// [employeeId] must reference an existing, non-deleted Employees row
  /// that doesn't already have an account linked — AuthRepositoryImpl
  /// enforces both, and that [currentUser] is actually an Owner, the
  /// same way [createAdditionalOwner] does.
  Future<AuthUser> createEmployeeAccount({
    required String employeeId,
    required String username,
    required String email,
    required String password,
  });

  /// The location this device's current session is viewing —
  /// Architecture Section 7a's location switcher backing store. Reads
  /// `Sessions.activeLocationId` for the singleton 'current' session
  /// row; null if no session is active, or the session has never had a
  /// location resolved for it yet. Deliberately dumb: this method does
  /// NOT decide what a null result should fall back to (a single-
  /// location business's one-and-only location, say) — that resolution
  /// logic lives in `ResolveActiveLocation`
  /// (domain/usecases/active_location_resolver.dart), which is the only
  /// intended caller of this getter. Everything else in the app should
  /// go through that resolver, not this method directly.
  Future<String?> getActiveLocationId();

  /// Persists [locationId] as this device's active session location —
  /// the write side of the location switcher. Silently a no-op if no
  /// session is currently active (there is nothing to attach a location
  /// to). Called by `ResolveActiveLocation` once it settles on a
  /// location, and will also be the mechanism a future location-
  /// switcher UI writes through once an owner can change this at will.
  Future<void> setActiveLocationId(String locationId);
}
