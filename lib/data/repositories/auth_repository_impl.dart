import 'package:drift/drift.dart';
import 'package:ulid/ulid.dart';

import '../../core/errors/failure.dart';
import '../../core/security/pin_hasher.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/repositories/audit_repository.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/permission_repository.dart';
import '../local/database/database.dart';

/// Architecture Section 6's login flow, entirely local now — Architecture
/// Redesign: no ApiClient, no AuthApi, no SecureStorage-held refresh
/// token. The Users table (tables.dart) is this device's own source of
/// truth; Sessions (also tables.dart) just says which Users row is
/// currently active.
///
/// SIMPLIFICATION pass: PasswordHasher/Argon2PasswordHasher is no longer
/// a dependency of this class — nothing below hashes or verifies a
/// password, since local identities no longer have one (see
/// AuthRepository's own doc comment). It's still exactly the right tool
/// for the future cross-device sync credential that doc comment
/// describes, and stays available in core/security/password_hasher.dart
/// for whatever constructs that feature later; there was simply nothing
/// left in THIS class to still call it, and an injected dependency
/// nothing here reads is a real unused_field, not a hypothetical one, so
/// it's removed rather than kept as an inert parameter.
class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required AppDatabase db,
    required PinHasher pinHasher,
    required AuditRepository auditRepository,
    required PermissionRepository permissionRepository,
  })  : _db = db,
        _pinHasher = pinHasher,
        _auditRepository = auditRepository,
        _permissionRepository = permissionRepository;

  final AppDatabase _db;
  final PinHasher _pinHasher;
  final AuditRepository _auditRepository;
  // Deliberately not required by createFirstOwner/createAdditionalOwner
  // — an Owner login is structurally exempt from every permission check
  // (PermissionRepository.hasPermission short-circuits on
  // AuthRole.owner before ever touching this), so seeding a stored
  // grant for one would just be a row nothing ever reads. Only
  // createEmployeeAccount below calls this.
  final PermissionRepository _permissionRepository;

  // Mirrors auth_service.py's own module-level constants exactly
  // (verified directly) — see failure.dart's _AccountLocked doc comment
  // for why this throttle still matters with no network involved at
  // all: it defends against someone with physical access to the device
  // guessing a credential, which has nothing to do with networking. As
  // of the onboarding-simplification pass this throttles loginPin
  // guesses (switchLocalUser) the same way it always throttled password
  // guesses — a short PIN's smaller keyspace needs this defense at
  // least as much as a password did, arguably more.
  static const _maxFailedLoginAttempts = 5;
  static const _lockoutDuration = Duration(minutes: 15);

  // Same 4-digit floor settings_main_screen.dart's own approval-PIN
  // setup already established as this app's PIN-length convention —
  // matched here rather than invented separately, so both PIN concepts
  // enforce the same floor for the same reason.
  static const _minPinLength = 4;

  AuthUser? _currentUser;

  @override
  AuthUser? get currentUser => _currentUser;

  @override
  Future<bool> hasAnyOwnerAccount() async {
    // Specifically an Owner-role row, not just any row — this table
    // also holds Employee-role rows (see createEmployeeAccount below),
    // so "any row exists" and "an Owner exists" are genuinely different
    // questions; this method's own name promises the second one.
    //
    // Filters in Dart after fetching, rather than a WHERE clause on the
    // enum column itself — this codebase has no existing precedent
    // anywhere for comparing a textEnum column either in a query
    // builder or against a returned row, so there's nothing to verify
    // the exact API against without a working Dart toolchain. The
    // table will realistically hold a handful of rows at most (local
    // accounts on one device), so fetching all of them costs nothing
    // meaningful — favoring the lower-risk, easily-verified approach
    // over a shorter but unverifiable one.
    final allUsers = await _db.select(_db.users).get();
    return allUsers.any((u) => u.role == AuthRole.owner);
  }

  @override
  Future<AuthUser?> restoreSession() async {
    final session =
        await (_db.select(_db.sessions)..where((s) => s.id.equals('current')))
            .getSingleOrNull();
    if (session == null) return null;

    final userRow = await (_db.select(_db.users)
          ..where((u) => u.localId.equals(session.userId)))
        .getSingleOrNull();

    // The session points at a user row that's gone or been deactivated
    // (Volume 9's access-revocation case) — the local equivalent of the
    // old "the stored refresh token is genuinely no longer valid"
    // branch. Presenting "signed in as X" from a stale session pointer
    // when that account can no longer sign in would be actively
    // misleading, not just stale, so this clears the session rather
    // than returning it.
    if (userRow == null || !userRow.isActive) {
      await _clearSession();
      return null;
    }

    _currentUser = _toAuthUser(userRow);
    return _currentUser;
  }

  @override
  Future<AuthUser> createFirstOwner({required String fullName}) async {
    if (await hasAnyOwnerAccount()) {
      // Mirrors the shape of a genuine business-rule rejection
      // (BusinessRuleFailure, per failure.dart) rather than a generic
      // exception — this is a deliberate rule, not a defect: this
      // method exists specifically for the zero-account case.
      throw const BusinessRuleFailure(
        'An owner account already exists on this device.',
      );
    }

    final user = await _insertLocalIdentity(
      fullName: fullName,
      role: AuthRole.owner,
      pin: null,
    );

    // Collapsed into one step rather than create-then-separately-log-in
    // — see AuthRepository.createFirstOwner's own doc comment for why.
    _currentUser = user;
    await _persistSession(user);
    // Mirrors the backend's own BOOTSTRAP_ADMIN action name exactly
    // (verified directly against routers/auth.py); details payload
    // changed from created_username to created_full_name since the
    // former no longer exists for a local-only identity.
    await _auditRepository.log(
      action: 'BOOTSTRAP_ADMIN',
      module: 'AUTH',
      userId: user.id,
      recordId: user.id,
      details: {'created_full_name': user.fullName},
    );
    return user;
  }

  @override
  Future<void> setOwnLoginPin({required String pin}) async {
    final acting = _currentUser;
    if (acting == null) {
      throw const AuthFailure.forbidden();
    }
    _validatePin(pin);
    final hashed = await _pinHasher.hash(pin);
    await (_db.update(_db.users)..where((u) => u.localId.equals(acting.id)))
        .write(
      UsersCompanion(
        loginPinHash: Value(hashed.hash),
        loginPinSalt: Value(hashed.salt),
        updatedAt: Value(DateTime.now()),
      ),
    );
    _currentUser = AuthUser(
      id: acting.id,
      username: acting.username,
      email: acting.email,
      fullName: acting.fullName,
      role: acting.role,
      isActive: acting.isActive,
      hasLoginPin: true,
    );
  }

  @override
  Future<List<AuthUser>> listLocalIdentities() async {
    final rows = await _db.select(_db.users).get();
    return rows.map(_toAuthUser).toList();
  }

  @override
  Future<AuthUser> switchLocalUser({
    required String userId,
    String? pin,
  }) async {
    final userRow = await (_db.select(_db.users)
          ..where((u) => u.localId.equals(userId)))
        .getSingleOrNull();

    // Deliberately a generic failure rather than "no such user" — same
    // don't-let-an-enumeration-attempt-learn-anything reasoning the old
    // username+password login already applied (auth_service.py's
    // authenticate_user, verified directly), even though the picker UI
    // realistically only ever passes an id it just listed itself.
    if (userRow == null) {
      throw const AuthFailure.invalidCredentials();
    }

    if (userRow.lockedUntil != null &&
        userRow.lockedUntil!.isAfter(DateTime.now())) {
      await _auditRepository.log(
        action: 'LOGIN_BLOCKED_LOCKOUT',
        module: 'AUTH',
        details: {'user_id': userId},
      );
      throw AuthFailure.accountLocked(lockedUntil: userRow.lockedUntil!);
    }

    final pinHash = userRow.loginPinHash;
    final pinSalt = userRow.loginPinSalt;

    // No PIN set at all — the sole-local-user case (see this method's
    // own doc comment on AuthRepository). Nothing to verify [pin]
    // against, so it's ignored entirely rather than rejected: there is
    // no PIN this identity was ever asked to set, so there's nothing a
    // caller could have gotten "wrong." isActive is still checked below
    // either way — this only skips the PIN check, not every check.
    final hasPinSet = pinHash != null && pinSalt != null;

    if (hasPinSet) {
      if (pin == null) {
        throw const AuthFailure.invalidCredentials();
      }
      final pinMatches = await _pinHasher.verify(
        pin,
        expectedHash: pinHash,
        salt: pinSalt,
      );

      if (!pinMatches) {
        final failedAttempts = userRow.failedLoginAttempts + 1;
        final lockingNow = failedAttempts >= _maxFailedLoginAttempts;
        await (_db.update(_db.users)..where((u) => u.localId.equals(userRow.localId)))
            .write(
          UsersCompanion(
            failedLoginAttempts: Value(failedAttempts),
            lockedUntil: lockingNow
                ? Value(DateTime.now().add(_lockoutDuration))
                : const Value.absent(),
            updatedAt: Value(DateTime.now()),
          ),
        );
        await _auditRepository.log(
          action: 'LOGIN_FAILED',
          module: 'AUTH',
          details: {'user_id': userId},
        );
        throw const AuthFailure.invalidCredentials();
      }
    }

    // isActive is checked here — after the PIN matches (or is skipped
    // entirely for a PIN-less identity), before resetting the failure
    // counter — deliberately, not incidentally: checking it before the
    // PIN would let a wrong-PIN attempt on a deactivated account learn
    // that the account exists at all, and checking it only via the
    // counter-reset would skip it on a first-try-correct PIN entirely.
    // This mirrors auth_service.py's authenticate_user's own check order
    // (verified directly). Without it, a deactivated account (Volume 9's
    // access-revocation flow) could still switch to successfully as
    // long as the PIN was still correct — or, for a PIN-less identity,
    // unconditionally.
    if (!userRow.isActive) {
      await _auditRepository.log(
        action: 'LOGIN_FAILED',
        module: 'AUTH',
        details: {'user_id': userId},
      );
      throw const AuthFailure.accountDeactivated();
    }

    // Successful switch resets the failed-attempt counter — same
    // reasoning as the old login method: only on success, not just on
    // an explicit unlock.
    if (userRow.failedLoginAttempts != 0) {
      await (_db.update(_db.users)..where((u) => u.localId.equals(userRow.localId)))
          .write(
        UsersCompanion(
          failedLoginAttempts: const Value(0),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }

    final user = _toAuthUser(userRow);
    _currentUser = user;
    await _persistSession(user);
    await _auditRepository.log(action: 'LOGIN', module: 'AUTH', userId: user.id);
    return user;
  }

  @override
  Future<AuthUser> createAdditionalOwner({
    required String fullName,
    required String pin,
  }) async {
    final acting = _currentUser;
    // The local check IS the real enforcement now — see
    // AuthFailure.forbidden's doc comment in failure.dart.
    if (acting?.role != AuthRole.owner) {
      throw const AuthFailure.forbidden();
    }
    // See setOwnLoginPin's own doc comment: this repository never
    // invents a PIN for the acting owner on their behalf — they must
    // have chosen their own already.
    if (!acting!.hasLoginPin) {
      throw const BusinessRuleFailure(
        'Set your own PIN before adding another person to this device.',
      );
    }

    // Deliberately does NOT touch _currentUser or the Sessions table —
    // unlike createFirstOwner, there is already a signed-in owner, and
    // creating a co-owner's identity (Volume 9, Decision 33) doesn't
    // sign the acting owner out or sign the new identity in. The new
    // owner switches in separately, via switchLocalUser, whenever they
    // actually pick up the device.
    final newOwner = await _insertLocalIdentity(
      fullName: fullName,
      role: AuthRole.owner,
      pin: pin,
    );
    // Mirrors the backend's own admin-creates-user CREATE action shape
    // exactly (verified directly) — userId is the ACTING owner (matches
    // the backend's user_id=admin.id), recordId is the newly created
    // identity; details payload changed from created_username to
    // created_full_name, same reason as createFirstOwner's.
    await _auditRepository.log(
      action: 'CREATE',
      module: 'AUTH',
      userId: acting.id,
      recordId: newOwner.id,
      details: {'created_full_name': newOwner.fullName},
    );
    return newOwner;
  }

  @override
  Future<AuthUser> createEmployeeAccount({
    required String employeeId,
    required String pin,
    AuthRole role = AuthRole.employee,
  }) async {
    // See AuthRepository.createEmployeeAccount's own doc comment — this
    // method provisions a non-owner login only; createAdditionalOwner
    // is the (separate, more tightly gated) path for a second Owner.
    if (role == AuthRole.owner) {
      throw const BusinessRuleFailure(
        'Use createAdditionalOwner to add another owner.',
      );
    }
    final acting = _currentUser;
    // Same enforcement as createAdditionalOwner — only an Owner who has
    // already set their own PIN can provision a login for someone else.
    if (acting?.role != AuthRole.owner) {
      throw const AuthFailure.forbidden();
    }
    if (!acting!.hasLoginPin) {
      throw const BusinessRuleFailure(
        'Set your own PIN before adding another person to this device.',
      );
    }

    final employeeRow = await (_db.select(_db.employees)
          ..where((e) => e.id.equals(employeeId) & e.deletedAt.isNull()))
        .getSingleOrNull();
    if (employeeRow == null) {
      throw const BusinessRuleFailure(
        'No such employee on this device\'s roster.',
      );
    }
    if (employeeRow.authUserId != null) {
      throw const BusinessRuleFailure(
        'This employee already has a login account.',
      );
    }

    // Reuses the exact same creation path createFirstOwner/
    // createAdditionalOwner use — just with [role] (Manager, Cashier,
    // or the generic Employee fallback) instead of AuthRole.owner, and
    // the new identity's display name taken from the roster entry
    // already on file rather than re-collected here. No username/
    // email/password to collect at all anymore — pin is the entire
    // credential now.
    final newAccount = await _insertLocalIdentity(
      fullName: employeeRow.fullName,
      role: role,
      pin: pin,
    );

    await (_db.update(_db.employees)..where((e) => e.id.equals(employeeId)))
        .write(
      EmployeesCompanion(
        authUserId: Value(newAccount.id),
        updatedAt: Value(DateTime.now()),
      ),
    );

    // Seeds this brand-new login's stored permission grant from its
    // role preset — see PermissionRepository.seedDefaultsForNewAccount's
    // own doc comment. The owner can immediately adjust individual
    // permissions afterward from the employee's detail screen; this is
    // only the starting point.
    await _permissionRepository.seedDefaultsForNewAccount(
      userId: newAccount.id,
      role: role,
      grantedBy: acting.id,
    );

    // Same CREATE/AUTH shape as createAdditionalOwner's own audit entry,
    // plus which roster row this account now maps to and which role
    // preset it started with.
    await _auditRepository.log(
      action: 'CREATE',
      module: 'AUTH',
      userId: acting.id,
      recordId: newAccount.id,
      details: {
        'created_full_name': newAccount.fullName,
        'linked_employee_id': employeeId,
        'role': role.name,
      },
    );
    return newAccount;
  }

  @override
  Future<void> logout() async {
    final signedOutUserId = _currentUser?.id;
    await _clearSession();
    _currentUser = null;
    // Was also a best-effort call to the backend's own audit-log
    // endpoint (POST /api/auth/logout existed purely to record this);
    // now a direct local write, no network round-trip needed for it to
    // still happen reliably.
    await _auditRepository.log(action: 'LOGOUT', module: 'AUTH', userId: signedOutUserId);
  }

  /// pin.length < _minPinLength check shared by every call site that
  /// hashes a NEW pin (setOwnLoginPin, and _insertLocalIdentity when
  /// [pin] is non-null) — the same floor settings_main_screen.dart's
  /// approval-PIN setup already enforces client-side, applied here too
  /// as the repository-level backstop, the same defense-in-depth shape
  /// PasswordPolicy.validate used to provide for a new password before
  /// this pass.
  void _validatePin(String pin) {
    if (pin.length < _minPinLength) {
      throw ValidationFailure(
        fieldErrors: {'pin': 'Use at least $_minPinLength digits.'},
      );
    }
  }

  /// Shared by createFirstOwner, createAdditionalOwner, and
  /// createEmployeeAccount — inserts one new Users row. [pin] is null
  /// only for createFirstOwner's lone-local-user case (see that
  /// method's own doc comment); every other caller passes one, hashed
  /// here with the same Argon2PinHasher approvalPinHash already uses.
  /// No username/email/uniqueness check anymore — those columns are
  /// simply left null for a local-only identity (see tables.dart's
  /// ONBOARDING SIMPLIFICATION NOTE), and a local identity's fullName
  /// was never required to be unique even before this pass (real
  /// people share names; the ULID primary key is what's actually
  /// unique). Two different local identities landing on the same PIN
  /// by coincidence is likewise harmless and deliberately unchecked:
  /// the picker screen disambiguates by NAME first (tap a specific
  /// person, then enter a PIN checked only against that one row), so
  /// nothing about switchLocalUser's own correctness depends on PINs
  /// being unique across rows the way it would for a PIN-only, no-name
  /// entry scheme.
  Future<AuthUser> _insertLocalIdentity({
    required String fullName,
    required AuthRole role,
    required String? pin,
  }) async {
    String? pinHash;
    String? pinSalt;
    if (pin != null) {
      _validatePin(pin);
      final hashed = await _pinHasher.hash(pin);
      pinHash = hashed.hash;
      pinSalt = hashed.salt;
    }

    final localId = Ulid().toString();
    final now = DateTime.now();

    await _db.into(_db.users).insert(
          UsersCompanion.insert(
            localId: localId,
            fullName: fullName,
            role: role,
            loginPinHash: Value(pinHash),
            loginPinSalt: Value(pinSalt),
            createdAt: now,
            updatedAt: now,
          ),
        );

    return AuthUser(
      id: localId,
      fullName: fullName,
      role: role,
      isActive: true,
      hasLoginPin: pin != null,
    );
  }

  @override
  Future<String?> getActiveLocationId() async {
    final session = await (_db.select(_db.sessions)
          ..where((s) => s.id.equals('current')))
        .getSingleOrNull();
    return session?.activeLocationId;
  }

  @override
  Future<void> setActiveLocationId(String locationId) async {
    await (_db.update(_db.sessions)..where((s) => s.id.equals('current'))).write(
      SessionsCompanion(activeLocationId: Value(locationId)),
    );
  }

  /// Writes the signed-in user as this device's active session — called
  /// on every successful createFirstOwner, setOwnLoginPin's related
  /// callers, and switchLocalUser. A fixed 'current' id (matching
  /// Sessions' own singleton design, tables.dart), deleted and
  /// re-inserted unconditionally rather than upserted — enforcing "at
  /// most one active session" even when a different user switches in
  /// without an intervening clean logout (app force-closed, etc).
  ///
  /// Reads whatever the outgoing session row had for activeLocationId
  /// and carries it forward onto the new row, rather than starting that
  /// field over at null: the location is a property of the
  /// device/counter this app is running on, not of whichever person is
  /// currently signed in on it, so a different local identity switching
  /// in on the same till has no reason to reset which location the
  /// screen is showing. This matters concretely because
  /// [setActiveLocationId] is a real, called write path
  /// (`ResolveActiveLocation`, domain/usecases/) — resetting it here on
  /// every switch would undo that resolver's own work on every switch.
  ///
  /// Only an outgoing row that still exists gets carried forward — an
  /// explicit [logout] deletes the row outright first, so sign-out then
  /// switch-back-in starts genuinely fresh; there's nothing left at
  /// that point for this method to read.
  Future<void> _persistSession(AuthUser user) async {
    await _db.transaction(() async {
      final outgoing = await (_db.select(_db.sessions)
            ..where((s) => s.id.equals('current')))
          .getSingleOrNull();
      await (_db.delete(_db.sessions)..where((s) => s.id.equals('current'))).go();
      await _db.into(_db.sessions).insert(
            SessionsCompanion.insert(
              id: 'current',
              userId: user.id,
              activeLocationId: Value(outgoing?.activeLocationId),
            ),
          );
    });
  }

  Future<void> _clearSession() async {
    await (_db.delete(_db.sessions)..where((s) => s.id.equals('current'))).go();
  }

  AuthUser _toAuthUser(UserRow row) => AuthUser(
        id: row.localId,
        username: row.username,
        email: row.email,
        fullName: row.fullName,
        role: row.role,
        isActive: row.isActive,
        hasLoginPin: row.loginPinHash != null,
      );
}
