import 'package:drift/drift.dart';
import 'package:ulid/ulid.dart';

import '../../core/errors/failure.dart';
import '../../core/security/password_hasher.dart';
import '../../core/security/password_policy.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/repositories/audit_repository.dart';
import '../../domain/repositories/auth_repository.dart';
import '../local/database/database.dart';

/// Architecture Section 6's login flow, entirely local now — Architecture
/// Redesign: no ApiClient, no AuthApi, no SecureStorage-held refresh
/// token. The Users table (tables.dart) is this device's own source of
/// truth; Sessions (also tables.dart) just says which Users row is
/// currently active.
class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required AppDatabase db,
    required PasswordHasher passwordHasher,
    required AuditRepository auditRepository,
  })  : _db = db,
        _passwordHasher = passwordHasher,
        _auditRepository = auditRepository;

  final AppDatabase _db;
  final PasswordHasher _passwordHasher;
  final AuditRepository _auditRepository;

  // Mirrors auth_service.py's own module-level constants exactly
  // (verified directly) — see failure.dart's _AccountLocked doc comment
  // for why this throttle still matters with no network involved at
  // all: it defends against someone with physical access to the device
  // guessing a credential, which has nothing to do with networking.
  static const _maxFailedLoginAttempts = 5;
  static const _lockoutDuration = Duration(minutes: 15);

  AuthUser? _currentUser;

  @override
  AuthUser? get currentUser => _currentUser;

  @override
  Future<bool> hasAnyOwnerAccount() async {
    // Specifically an Owner-role row, not just any row — CORRECTED:
    // currently equivalent to "any row at all" only by accident, since
    // nothing yet writes an Employee-role row to this same Users table
    // (that path doesn't exist until a future Sync/Employees stage adds
    // accepting an invite). The method's own name is a promise about
    // Owner specifically; checking role explicitly keeps that promise
    // true regardless of what gets built into this table later, rather
    // than relying on today's coincidence.
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
  Future<AuthUser> createFirstOwner({
    required String username,
    required String email,
    required String fullName,
    required String password,
  }) async {
    if (await hasAnyOwnerAccount()) {
      // Mirrors the shape of a genuine business-rule rejection
      // (BusinessRuleFailure, per failure.dart) rather than a generic
      // exception — this is a deliberate rule, not a defect: this
      // method exists specifically for the zero-account case.
      throw const BusinessRuleFailure(
        'An owner account already exists on this device.',
      );
    }

    final user = await _createLocalUser(
      username: username,
      email: email,
      fullName: fullName,
      password: password,
      role: AuthRole.owner,
    );

    // Collapsed into one step rather than create-then-separately-log-in
    // — see AuthRepository.createFirstOwner's own doc comment for why.
    _currentUser = user;
    await _persistSession(user);
    // Mirrors the backend's own BOOTSTRAP_ADMIN action name and details
    // shape exactly (verified directly against routers/auth.py).
    await _auditRepository.log(
      action: 'BOOTSTRAP_ADMIN',
      module: 'AUTH',
      userId: user.id,
      recordId: user.id,
      details: {'created_username': user.username},
    );
    return user;
  }

  @override
  Future<AuthUser> login({
    required String username,
    required String password,
  }) async {
    final userRow = await (_db.select(_db.users)
          ..where((u) => u.username.equals(username)))
        .getSingleOrNull();

    // Deliberately the same generic message whether the username
    // doesn't exist at all or the password is wrong for one that does —
    // mirrors auth_service.py's authenticate_user exactly (verified
    // directly: it raises the identical AuthenticationError either way),
    // so a local account-enumeration attempt learns nothing from the
    // difference.
    if (userRow == null) {
      await _auditRepository.log(
        action: 'LOGIN_FAILED',
        module: 'AUTH',
        details: {'username': username},
      );
      throw const AuthFailure.invalidCredentials();
    }

    if (userRow.lockedUntil != null && userRow.lockedUntil!.isAfter(DateTime.now())) {
      await _auditRepository.log(
        action: 'LOGIN_BLOCKED_LOCKOUT',
        module: 'AUTH',
        details: {'username': username},
      );
      throw AuthFailure.accountLocked(lockedUntil: userRow.lockedUntil!);
    }

    final passwordMatches = await _passwordHasher.verify(
      password,
      expectedHash: userRow.hashedPassword,
      salt: userRow.passwordSalt,
    );

    if (!passwordMatches) {
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
        details: {'username': username},
      );
      throw const AuthFailure.invalidCredentials();
    }

    // BUG FIX (self-audit pass, after Stage 4): this check was missing
    // entirely — auth_service.py's authenticate_user checks is_active
    // here, in this exact position (after the password matches, before
    // resetting the failure counter), verified by re-reading the source
    // a second time specifically to check this. Without it, a
    // deactivated account (Volume 9's access-revocation flow) could
    // still log in successfully as long as the password was still
    // correct.
    if (!userRow.isActive) {
      await _auditRepository.log(
        action: 'LOGIN_FAILED',
        module: 'AUTH',
        details: {'username': username},
      );
      throw const AuthFailure.accountDeactivated();
    }

    // Successful login resets the failed-attempt counter — mirrors
    // auth_service.py's authenticate_user exactly (verified directly:
    // it zeroes failed_login_attempts on success, not just on an
    // explicit unlock).
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
    required String username,
    required String email,
    required String fullName,
    required String password,
  }) async {
    // The local check IS the real enforcement now — see
    // AuthFailure.forbidden's doc comment in failure.dart.
    if (_currentUser?.role != AuthRole.owner) {
      throw const AuthFailure.forbidden();
    }

    // Deliberately does NOT touch _currentUser or the Sessions table —
    // unlike createFirstOwner, there is already a signed-in owner, and
    // creating a co-owner's account (Volume 9, Decision 33) doesn't sign
    // the acting owner out or sign the new account in. The new owner
    // logs in separately, the normal way, whenever they actually pick up
    // the device.
    final newOwner = await _createLocalUser(
      username: username,
      email: email,
      fullName: fullName,
      password: password,
      role: AuthRole.owner,
    );
    // Mirrors the backend's own admin-creates-user CREATE action and
    // details shape exactly (verified directly) — userId is the ACTING
    // owner (matches the backend's user_id=admin.id), recordId is the
    // newly created account.
    await _auditRepository.log(
      action: 'CREATE',
      module: 'AUTH',
      userId: _currentUser!.id,
      recordId: newOwner.id,
      details: {'created_username': newOwner.username},
    );
    return newOwner;
  }

  @override
  Future<AuthUser> createEmployeeAccount({
    required String employeeId,
    required String username,
    required String email,
    required String password,
  }) async {
    // Same enforcement as createAdditionalOwner — only an Owner can
    // provision a login for someone else.
    if (_currentUser?.role != AuthRole.owner) {
      throw const AuthFailure.forbidden();
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
    // createAdditionalOwner use — same password-policy check, same
    // username/email uniqueness check, same hashing — just with
    // AuthRole.employee instead of AuthRole.owner, and the new
    // account's display name taken from the roster entry already on
    // file rather than re-collected here.
    final newAccount = await _createLocalUser(
      username: username,
      email: email,
      fullName: employeeRow.fullName,
      password: password,
      role: AuthRole.employee,
    );

    await (_db.update(_db.employees)..where((e) => e.id.equals(employeeId)))
        .write(
      EmployeesCompanion(
        authUserId: Value(newAccount.id),
        updatedAt: Value(DateTime.now()),
      ),
    );

    // Same CREATE/AUTH shape as createAdditionalOwner's own audit entry,
    // plus which roster row this account now maps to.
    await _auditRepository.log(
      action: 'CREATE',
      module: 'AUTH',
      userId: _currentUser!.id,
      recordId: newAccount.id,
      details: {
        'created_username': newAccount.username,
        'linked_employee_id': employeeId,
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

  /// Shared by createFirstOwner and createAdditionalOwner — mirrors
  /// auth_service.py's create_user exactly (verified directly):
  /// password-strength check, then username/email uniqueness, in that
  /// order, both as the same DuplicateError-equivalent
  /// (BusinessRuleFailure here, matching how ApiClient.mapError bucketed
  /// a 409 — verified directly, not assumed).
  Future<AuthUser> _createLocalUser({
    required String username,
    required String email,
    required String fullName,
    required String password,
    required AuthRole role,
  }) async {
    // Throws ValidationFailure itself if this doesn't pass.
    PasswordPolicy.validate(password);

    final usernameTaken = await (_db.select(_db.users)
          ..where((u) => u.username.equals(username)))
        .getSingleOrNull();
    if (usernameTaken != null) {
      throw const BusinessRuleFailure('Username already taken.');
    }

    final emailTaken =
        await (_db.select(_db.users)..where((u) => u.email.equals(email)))
            .getSingleOrNull();
    if (emailTaken != null) {
      throw const BusinessRuleFailure('Email already registered.');
    }

    final passwordHash = await _passwordHasher.hash(password);
    final localId = Ulid().toString();
    final now = DateTime.now();

    await _db.into(_db.users).insert(
          UsersCompanion.insert(
            localId: localId,
            username: username,
            email: email,
            fullName: fullName,
            hashedPassword: passwordHash.hash,
            passwordSalt: passwordHash.salt,
            role: role,
            createdAt: now,
            updatedAt: now,
          ),
        );

    return AuthUser(
      id: localId,
      username: username,
      email: email,
      fullName: fullName,
      role: role,
      isActive: true,
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
  /// on every successful createFirstOwner and login. A fixed 'current'
  /// id (matching Sessions' own singleton design, tables.dart), deleted
  /// and re-inserted unconditionally rather than upserted — enforcing
  /// "at most one active session" for the same edge case as before this
  /// redesign: a different user signing in without an intervening clean
  /// logout (app force-closed, etc).
  ///
  /// CORRECTED: activeLocationId used to be dropped unconditionally on
  /// every call ("no location-switcher UI exists yet to make preserving
  /// it across a re-login actually matter (Phase 2)"). Phase 2 is now:
  /// [setActiveLocationId] is a real, called write path
  /// (`ResolveActiveLocation`), so silently wiping it here would be a
  /// real regression, not a harmless simplification anymore. This now
  /// reads whatever the outgoing session had and carries it forward —
  /// the location is a property of the device/counter, not the
  /// signed-in user, so there's no reason a different user signing in
  /// on the same till should reset it.
  ///
  /// Only reaches an existing row to preserve when this method runs
  /// without an intervening [_clearSession] — [login] goes straight to
  /// this method with no clear step first, so signing in again while a
  /// session row already exists (this method's own original scenario:
  /// "a different user signing in without an intervening clean logout,
  /// app force-closed, etc") does carry it forward. An explicit
  /// [logout] deletes the row outright first, so that specific path —
  /// sign out, then sign back in — starts genuinely fresh; there's
  /// nothing left at that point for this method to read.
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
      );
}
