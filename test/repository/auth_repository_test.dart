import 'package:fulus_mobile/core/errors/failure.dart';
import 'package:fulus_mobile/core/security/pin_hasher.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/repositories/auth_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/auth_user.dart';
import 'package:fulus_mobile/domain/repositories/audit_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

/// Deterministic, pure-Dart fake — same reasoning as
/// approval_pin_repository_test.dart's own _FakePinHasher (that exact
/// class can't be reused directly across files, being private to its
/// own library, so this mirrors it rather than importing it): keeps
/// this repository's own tests fast and independent of
/// Argon2PinHasher's correctness, which pin_hasher_test.dart covers
/// directly.
class _FakePinHasher implements PinHasher {
  @override
  Future<PinHash> hash(String pin) async {
    return PinHash(hash: 'fake-hash:$pin', salt: 'fake-salt:$pin');
  }

  @override
  Future<bool> verify(
    String pin, {
    required String expectedHash,
    required String salt,
  }) async {
    return expectedHash == 'fake-hash:$pin' && salt == 'fake-salt:$pin';
  }
}

class MockAuditRepository extends Mock implements AuditRepository {}

/// Inserts a minimal Employees roster row directly — standing in for
/// whatever screen normally adds someone to the roster (out of scope
/// for this repository's own tests), the same way the pre-simplification
/// version of this file never needed to construct one at all since
/// createEmployeeAccount didn't exist as a case yet.
Future<void> _insertRosterEmployee(
  AppDatabase db, {
  required String id,
  required String fullName,
}) async {
  final now = DateTime.now();
  await db.into(db.employees).insert(
        EmployeesCompanion.insert(
          id: id,
          fullName: fullName,
          createdAt: now,
          updatedAt: now,
        ),
      );
}

void main() {
  late MockAuditRepository auditRepository;
  late AppDatabase db;
  late AuthRepositoryImpl repository;

  setUp(() {
    auditRepository = MockAuditRepository();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = AuthRepositoryImpl(
      db: db,
      pinHasher: _FakePinHasher(),
      auditRepository: auditRepository,
    );

    when(() => auditRepository.log(
          userId: any(named: 'userId'),
          action: any(named: 'action'),
          module: any(named: 'module'),
          recordId: any(named: 'recordId'),
          details: any(named: 'details'),
        )).thenAnswer((_) async {});
  });

  tearDown(() async {
    await db.close();
  });

  group('hasAnyOwnerAccount', () {
    test('false on a fresh install', () async {
      expect(await repository.hasAnyOwnerAccount(), isFalse);
    });

    test('true once an account exists', () async {
      await repository.createFirstOwner(fullName: 'Chidinma Okafor');
      expect(await repository.hasAnyOwnerAccount(), isTrue);
    });
  });

  group('createFirstOwner', () {
    test('creates the account with no PIN, signs it in, records BOOTSTRAP_ADMIN',
        () async {
      final user = await repository.createFirstOwner(fullName: 'Chidinma Okafor');

      expect(user.role, AuthRole.owner);
      expect(user.hasLoginPin, isFalse);
      expect(repository.currentUser?.fullName, 'Chidinma Okafor');

      verify(() => auditRepository.log(
            action: 'BOOTSTRAP_ADMIN',
            module: 'AUTH',
            userId: user.id,
            recordId: user.id,
            details: {'created_full_name': 'Chidinma Okafor'},
          )).called(1);
    });

    test('rejects a second call once an account already exists', () async {
      await repository.createFirstOwner(fullName: 'Chidinma Okafor');

      await expectLater(
        repository.createFirstOwner(fullName: 'Ngozi Eze'),
        throwsA(isA<BusinessRuleFailure>()),
      );
    });
  });

  group('setOwnLoginPin', () {
    test('sets a PIN for the currently signed-in user', () async {
      await repository.createFirstOwner(fullName: 'Chidinma Okafor');
      expect(repository.currentUser?.hasLoginPin, isFalse);

      await repository.setOwnLoginPin(pin: '1234');

      expect(repository.currentUser?.hasLoginPin, isTrue);
    });

    test('rejects a PIN shorter than 4 digits', () async {
      await repository.createFirstOwner(fullName: 'Chidinma Okafor');

      await expectLater(
        repository.setOwnLoginPin(pin: '12'),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('rejects the call when nobody is signed in', () async {
      await expectLater(
        repository.setOwnLoginPin(pin: '1234'),
        throwsA(isA<AuthFailure>()),
      );
    });
  });

  group('createAdditionalOwner', () {
    test('rejects an acting owner who has not set their own PIN yet', () async {
      await repository.createFirstOwner(fullName: 'Chidinma Okafor');

      await expectLater(
        repository.createAdditionalOwner(fullName: 'Ngozi Eze', pin: '2222'),
        throwsA(isA<BusinessRuleFailure>()),
      );
    });

    test('an owner with a PIN can create a co-owner identity', () async {
      await repository.createFirstOwner(fullName: 'Chidinma Okafor');
      await repository.setOwnLoginPin(pin: '1111');

      final coOwner =
          await repository.createAdditionalOwner(fullName: 'Ngozi Eze', pin: '2222');

      expect(coOwner.role, AuthRole.owner);
      expect(coOwner.hasLoginPin, isTrue);
      // Does NOT sign the acting owner out — see AuthRepository's own
      // doc comment on why this differs from createFirstOwner.
      expect(repository.currentUser?.fullName, 'Chidinma Okafor');
    });

    test('rejects the call when nobody is signed in', () async {
      await expectLater(
        repository.createAdditionalOwner(fullName: 'Ngozi Eze', pin: '2222'),
        throwsA(isA<AuthFailure>()),
      );
    });
  });

  group('createEmployeeAccount', () {
    test('rejects an acting owner who has not set their own PIN yet', () async {
      await repository.createFirstOwner(fullName: 'Chidinma Okafor');
      await _insertRosterEmployee(db, id: 'emp-1', fullName: 'Tunde Bakare');

      await expectLater(
        repository.createEmployeeAccount(employeeId: 'emp-1', pin: '3333'),
        throwsA(isA<BusinessRuleFailure>()),
      );
    });

    test('links a new account to the roster entry and takes its name', () async {
      await repository.createFirstOwner(fullName: 'Chidinma Okafor');
      await repository.setOwnLoginPin(pin: '1111');
      await _insertRosterEmployee(db, id: 'emp-1', fullName: 'Tunde Bakare');

      final account =
          await repository.createEmployeeAccount(employeeId: 'emp-1', pin: '3333');

      expect(account.role, AuthRole.employee);
      expect(account.fullName, 'Tunde Bakare');

      final employeeRow =
          await (db.select(db.employees)..where((e) => e.id.equals('emp-1'))).getSingle();
      expect(employeeRow.authUserId, account.id);
    });

    test('rejects an unknown employeeId', () async {
      await repository.createFirstOwner(fullName: 'Chidinma Okafor');
      await repository.setOwnLoginPin(pin: '1111');

      await expectLater(
        repository.createEmployeeAccount(employeeId: 'nonexistent', pin: '3333'),
        throwsA(isA<BusinessRuleFailure>()),
      );
    });

    test('rejects an employee who already has a login account', () async {
      await repository.createFirstOwner(fullName: 'Chidinma Okafor');
      await repository.setOwnLoginPin(pin: '1111');
      await _insertRosterEmployee(db, id: 'emp-1', fullName: 'Tunde Bakare');
      await repository.createEmployeeAccount(employeeId: 'emp-1', pin: '3333');

      await expectLater(
        repository.createEmployeeAccount(employeeId: 'emp-1', pin: '4444'),
        throwsA(isA<BusinessRuleFailure>()),
      );
    });
  });

  group('listLocalIdentities', () {
    test('lists every local identity created on this device', () async {
      final owner = await repository.createFirstOwner(fullName: 'Chidinma Okafor');
      await repository.setOwnLoginPin(pin: '1111');
      final coOwner =
          await repository.createAdditionalOwner(fullName: 'Ngozi Eze', pin: '2222');

      final identities = await repository.listLocalIdentities();

      expect(identities.map((u) => u.id), containsAll([owner.id, coOwner.id]));
    });
  });

  group('switchLocalUser', () {
    late String coOwnerId;

    setUp(() async {
      await repository.createFirstOwner(fullName: 'Chidinma Okafor');
      await repository.setOwnLoginPin(pin: '1111');
      final coOwner =
          await repository.createAdditionalOwner(fullName: 'Ngozi Eze', pin: '2222');
      coOwnerId = coOwner.id;
      clearInteractions(auditRepository);
      when(() => auditRepository.log(
            userId: any(named: 'userId'),
            action: any(named: 'action'),
            module: any(named: 'module'),
            recordId: any(named: 'recordId'),
            details: any(named: 'details'),
          )).thenAnswer((_) async {});
    });

    test('succeeds with the right PIN and records LOGIN', () async {
      final user = await repository.switchLocalUser(userId: coOwnerId, pin: '2222');

      expect(user.fullName, 'Ngozi Eze');
      expect(repository.currentUser?.fullName, 'Ngozi Eze');
      verify(() => auditRepository.log(action: 'LOGIN', module: 'AUTH', userId: user.id))
          .called(1);
    });

    test('fails for an unknown userId', () async {
      await expectLater(
        repository.switchLocalUser(userId: 'nonexistent', pin: 'whatever'),
        throwsA(isA<AuthFailure>()),
      );
    });

    test('rejects a deactivated account even with the correct PIN, mirroring '
        "auth_service.py's is_active check exactly. There is no public method yet "
        'to deactivate an account, so this writes directly to the table to '
        'simulate it.', () async {
      await (db.update(db.users)..where((u) => u.localId.equals(coOwnerId))).write(
        const UsersCompanion(isActive: Value(false)),
      );

      await expectLater(
        repository.switchLocalUser(userId: coOwnerId, pin: '2222'),
        throwsA(isA<AuthFailure>()),
      );
    });

    test('fails for the wrong PIN and records LOGIN_FAILED', () async {
      await expectLater(
        repository.switchLocalUser(userId: coOwnerId, pin: 'wrong'),
        throwsA(isA<AuthFailure>()),
      );
      verify(() => auditRepository.log(
            action: 'LOGIN_FAILED',
            module: 'AUTH',
            details: {'user_id': coOwnerId},
          )).called(1);
    });

    test('locks the identity after 5 failed attempts', () async {
      for (var i = 0; i < 5; i++) {
        await expectLater(
          repository.switchLocalUser(userId: coOwnerId, pin: 'wrong'),
          throwsA(isA<AuthFailure>()),
        );
      }

      // The 6th attempt — even with the CORRECT PIN — must now be
      // rejected as locked, not merely as another wrong-PIN failure,
      // since the account is locked before the PIN is even checked.
      await expectLater(
        repository.switchLocalUser(userId: coOwnerId, pin: '2222'),
        throwsA(isA<AuthFailure>()),
      );
      verify(() => auditRepository.log(
            action: 'LOGIN_BLOCKED_LOCKOUT',
            module: 'AUTH',
            details: {'user_id': coOwnerId},
          )).called(1);
    });

    test('a successful switch resets a nonzero failed-attempt count', () async {
      await expectLater(
        repository.switchLocalUser(userId: coOwnerId, pin: 'wrong'),
        throwsA(isA<AuthFailure>()),
      );

      await repository.switchLocalUser(userId: coOwnerId, pin: '2222');

      // Confirmed indirectly: 4 more wrong attempts (5 total since the
      // counter reset) must NOT lock the identity, since a successful
      // switch should have zeroed it back to 0 rather than leaving it
      // at 1 from the earlier failure.
      for (var i = 0; i < 4; i++) {
        await expectLater(
          repository.switchLocalUser(userId: coOwnerId, pin: 'wrong'),
          throwsA(isA<AuthFailure>()),
        );
      }
      final user = await repository.switchLocalUser(userId: coOwnerId, pin: '2222');
      expect(user.fullName, 'Ngozi Eze'); // would have thrown accountLocked otherwise
    });
  });

  group('switchLocalUser (sole local user, no PIN set)', () {
    test('succeeds with no PIN at all — see switchLocalUser\'s own doc '
        'comment on AuthRepository for why this is the sole-local-user '
        'case restoreSession normally handles instead', () async {
      final owner = await repository.createFirstOwner(fullName: 'Chidinma Okafor');
      await repository.logout();

      final user = await repository.switchLocalUser(userId: owner.id);

      expect(user.fullName, 'Chidinma Okafor');
      expect(repository.currentUser?.id, owner.id);
    });

    test('still rejects a deactivated PIN-less identity', () async {
      final owner = await repository.createFirstOwner(fullName: 'Chidinma Okafor');
      await repository.logout();
      await (db.update(db.users)..where((u) => u.localId.equals(owner.id))).write(
        const UsersCompanion(isActive: Value(false)),
      );

      await expectLater(
        repository.switchLocalUser(userId: owner.id),
        throwsA(isA<AuthFailure>()),
      );
    });
  });

  group('logout', () {
    test('clears the current user and restoreSession afterward returns null', () async {
      await repository.createFirstOwner(fullName: 'Chidinma Okafor');

      await repository.logout();

      expect(repository.currentUser, isNull);
      expect(await repository.restoreSession(), isNull);
    });
  });

  group('restoreSession', () {
    test('restores the signed-in user across a fresh repository instance', () async {
      final created = await repository.createFirstOwner(fullName: 'Chidinma Okafor');

      // A fresh instance over the SAME database, standing in for the
      // app restarting — the whole point of restoreSession existing.
      final restarted = AuthRepositoryImpl(
        db: db,
        pinHasher: _FakePinHasher(),
        auditRepository: auditRepository,
      );

      final restored = await restarted.restoreSession();

      expect(restored, isNotNull);
      expect(restored!.id, created.id);
      expect(restarted.currentUser?.id, created.id);
    });
  });

  group('getActiveLocationId / setActiveLocationId', () {
    test('is null before anything sets it', () async {
      await repository.createFirstOwner(fullName: 'Chidinma Okafor');
      expect(await repository.getActiveLocationId(), isNull);
    });

    test('returns whatever was set', () async {
      await repository.createFirstOwner(fullName: 'Chidinma Okafor');
      await repository.setActiveLocationId('loc-1');
      expect(await repository.getActiveLocationId(), 'loc-1');
    });

    test('is a no-op with no active session', () async {
      // No createFirstOwner/switchLocalUser call in this test — nothing
      // to attach a location to, and this should not throw.
      await repository.setActiveLocationId('loc-1');
      expect(await repository.getActiveLocationId(), isNull);
    });

    test('survives switching to a different local identity', () async {
      // Not a logout()-then-switch cycle — logout() deletes the
      // Sessions row outright (_clearSession), so there is nothing left
      // to preserve across that specific path; this is the scenario
      // _persistSession's own doc comment describes: a different local
      // identity switching in without an intervening clean logout.
      // switchLocalUser goes straight to _persistSession with no
      // _clearSession first, so the prior session row (and its
      // activeLocationId) is still there for the new one to read and
      // carry forward.
      await repository.createFirstOwner(fullName: 'Chidinma Okafor');
      await repository.setOwnLoginPin(pin: '1111');
      final coOwner =
          await repository.createAdditionalOwner(fullName: 'Ngozi Eze', pin: '2222');
      await repository.setActiveLocationId('loc-1');

      await repository.switchLocalUser(userId: coOwner.id, pin: '2222');

      expect(await repository.getActiveLocationId(), 'loc-1');
    });
  });
}
