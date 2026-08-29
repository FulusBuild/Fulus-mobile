import '../entities/auth_user.dart';
import '../entities/permission.dart';

/// Architecture Section 6's login flow, re-scoped twice now: first by
/// the Architecture Redesign (local Business Engine, no server-issued
/// credentials, no client/server boundary for any of this), then by the
/// onboarding-simplification pass this doc comment describes. Every
/// method below is backed entirely by the local Users table
/// (AuthRepositoryImpl) — nothing here makes a network call.
///
/// SIMPLIFICATION: a username+email+password made sense when every
/// account had to authenticate across a network boundary; nothing here
/// does that anymore, so nothing here should still cost that much to
/// set up. What's actually needed locally is just enough to tell two
/// people on the same device apart — a name, and (only once there IS a
/// second person to tell apart from the first) a short PIN. A real
/// portable credential is still exactly the right tool for its one
/// remaining job — a future cross-device sync feature, not built yet —
/// which is why the Users table's username/email/hashedPassword columns
/// still exist (see tables.dart) rather than being removed outright;
/// they're just no longer what a local-only identity is required to
/// have.
///
/// The owner-approval PIN system is still deliberately NOT part of this
/// interface, for the same reason as before: it's a separate concern
/// with its own repository (ApprovalPinRepository), answering a
/// different question ("is this specific action authorized") from what
/// this interface answers ("who is currently using this device") — see
/// ApprovalPinRepository's own doc comment. That the local identity PIN
/// below and the approval PIN happen to both be short numeric secrets
/// hashed with the same Argon2PinHasher is a shared implementation
/// detail, not a sign these are the same concern.
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
  /// should show the identity picker instead. No server round-trip
  /// anymore: this is a plain local Users-table count.
  Future<bool> hasAnyOwnerAccount();

  /// Restores the active session at app launch (bootstrap.dart), before
  /// any UI is shown, per Architecture Section 6's "no login form, no
  /// blank splash screen" requirement for a returning user. Was: attempt
  /// a silent token refresh. Now: read which local user the Sessions
  /// table says is current, and return them — or null if there's no
  /// active session row, or the user it points to is no longer active
  /// (Volume 9's access-revocation case; see AuthFailure.sessionExpired's
  /// doc comment). Unaffected by the onboarding-simplification pass:
  /// this was never a credential check to begin with, just "which user
  /// id does the session row point at," so a null loginPin on that row
  /// changes nothing about how this method behaves. Null means show
  /// [hasAnyOwnerAccount] ? the identity picker (see
  /// [listLocalIdentities]) : account creation — never a password
  /// prompt; there's no longer a scenario in this interface where one
  /// would apply.
  Future<AuthUser?> restoreSession();

  /// Creates the very first local Owner identity and signs them in
  /// immediately — mirrors the backend's bootstrap_admin's "collapsed
  /// into one step, no redundant separate login" shape, just with no
  /// credential to collect first. [fullName] is genuinely all that's
  /// needed: a device with exactly one local user has nothing to
  /// distinguish that user FROM, so nothing here is deferred out of
  /// laziness — there is no more input a first run could ask for that
  /// would change how this method behaves. Must only be called when
  /// [hasAnyOwnerAccount] is false — AuthRepositoryImpl enforces this
  /// itself rather than trusting the caller to have checked.
  Future<AuthUser> createFirstOwner({required String fullName});

  /// Sets or replaces the CURRENTLY signed-in identity's own local PIN
  /// — mirrors ApprovalPinRepository.setOwnApprovalPin's naming and
  /// "always the caller's own account" shape exactly, for the same
  /// reason: an owner sets the PIN that identifies THEM, never one
  /// they're picking for someone else (that's what the [pin] parameter
  /// on [createAdditionalOwner]/[createEmployeeAccount] is for, and it
  /// exists specifically so this method never has to invent one on
  /// another identity's behalf). A device's sole local user has no
  /// reason to call this — see [createFirstOwner]'s own doc comment —
  /// so in practice this is called once, right before that same owner
  /// calls [createAdditionalOwner] or [createEmployeeAccount] for the
  /// first time; AuthRepositoryImpl requires it to have already been
  /// called before either of those will succeed, rather than silently
  /// assigning the acting owner a PIN they never chose.
  Future<void> setOwnLoginPin({required String pin});

  /// Every local identity on this device — id, name, role; never a
  /// hash or salt — for the "who's using this" picker [switchLocalUser]
  /// below needs whenever there's more than one. Deliberately returns
  /// the full list rather than taking a search term: this device
  /// realistically holds a handful of local accounts at most, the same
  /// judgment call [hasAnyOwnerAccount]'s own implementation already
  /// makes.
  Future<List<AuthUser>> listLocalIdentities();

  /// Switches the active session to a different already-existing local
  /// identity on this device — [userId] from [listLocalIdentities]. If
  /// that row has a PIN set, [pin] is checked against its
  /// loginPinHash/loginPinSalt with the same Argon2PinHasher
  /// approvalPinHash already uses, same lockout throttle a wrong
  /// password used to trigger before this pass. If it does NOT have a
  /// PIN set — the sole-local-user case [restoreSession] normally
  /// handles without ever reaching this method — this succeeds with no
  /// PIN required at all, [pin] ignored: there is nothing to
  /// distinguish that identity from, the same reasoning
  /// [createFirstOwner] already applies. This keeps the identity-picker
  /// screen able to call one method uniformly (tap a name, and either
  /// see a PIN field or go straight in) rather than needing a second,
  /// separate code path for an identity nobody has been asked to
  /// distinguish yet. Replaces the old username+password login entirely
  /// for same-device use; a future cross-device sync-restore flow gets
  /// its own method, built alongside that feature rather than left as
  /// an unused stub here now.
  Future<AuthUser> switchLocalUser({required String userId, String? pin});

  /// An already-signed-in Owner creates ANOTHER local Owner identity on
  /// this same device — Volume 9, Decision 33's co-equal-owners-sharing-
  /// a-till case (e.g. two owners, one physical counter). [pin] is
  /// required here (unlike [createFirstOwner]) precisely because this
  /// call means a second identity now exists to distinguish the first
  /// one from. AuthRepositoryImpl enforces two things before allowing
  /// this: that [currentUser] is actually an Owner (the local check IS
  /// the real enforcement now — see AuthFailure.forbidden's doc
  /// comment, not just UI convenience), and that the acting owner has
  /// already called [setOwnLoginPin] themselves — see that method's own
  /// doc comment for why this repository never assigns one on their
  /// behalf instead.
  Future<AuthUser> createAdditionalOwner({required String fullName, required String pin});

  /// Clears the local session. Was also a best-effort call to the
  /// backend's /api/auth/logout audit-log entry; gone along with the
  /// rest of the JWT-era plumbing — there's no remote session to record
  /// against anymore. AuthRepositoryImpl records a local LOGOUT audit
  /// entry directly instead (Stage 3: Audit Engine, since built) — no
  /// network round-trip needed for it to still happen reliably.
  Future<void> logout();

  /// An already-signed-in Owner sets up sign-in for an existing roster
  /// entry (Employees, EmployeeRepository), so that person can
  /// subsequently switch to their own identity on this same device
  /// rather than sharing the owner's. This is deliberately a
  /// same-device, owner-provisioned action — not a cross-device
  /// invite/QR-claim flow (Volume 9 describes one, but Employees is
  /// explicitly not a synced table in this architecture, so nothing
  /// about a roster entry is visible to a second device to claim
  /// against; a cross-device version is a later-phase capability once
  /// Employees has a sync story, not a Phase 0 one). [pin] replaces the
  /// former username+email+password entirely — the new account's
  /// display name is still taken from the roster entry already on
  /// file, same as before.
  ///
  /// [employeeId] must reference an existing, non-deleted Employees row
  /// that doesn't already have an account linked — AuthRepositoryImpl
  /// enforces both that and everything [createAdditionalOwner] enforces
  /// about the acting owner (must be an Owner, must already have called
  /// [setOwnLoginPin]).
  ///
  /// [role] is the new login's starting [AuthRole] — Manager, Cashier,
  /// or the generic Employee fallback (never Owner; use
  /// [createAdditionalOwner] for that). Defaults to [AuthRole.employee]
  /// only so this doesn't become a breaking signature change for any
  /// other caller; the actual "Set up login" UI always passes an
  /// explicit choice. AuthRepositoryImpl seeds this login's
  /// UserPermissions grant from [Permission.defaultsForRole] the moment
  /// the account is created — the owner can adjust individual
  /// permissions afterward from the employee's detail screen, which
  /// never touches [role] again once the login exists.
  Future<AuthUser> createEmployeeAccount({
    required String employeeId,
    required String pin,
    AuthRole role = AuthRole.employee,
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
