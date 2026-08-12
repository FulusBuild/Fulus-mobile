import 'package:fulus_mobile/core/errors/failure.dart';
import 'package:fulus_mobile/core/security/password_hasher.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/repositories/auth_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/auth_user.dart';
import 'package:fulus_mobile/domain/repositories/audit_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

/// Deterministic, pure-Dart fake — same reasoning as
/// approval_pin_repository_test.dart's own _FakePinHasher: keeps this
/// repository's own tests fast and independent of Argon2PasswordHasher's
/// correctness, which password_hasher_test.dart covers directly. (Real
/// Argon2id is deliberately slow — that's the point of it — so using
/// the real hasher here would needlessly cost every test in this file
/// that memory-hard computation just to exercise unrelated repository
/// logic.)
class _FakePasswordHasher implements PasswordHasher {
  @override
  Future<PasswordHash> hash(String password) async {
    return PasswordHash(hash: 'fake-hash:$password', salt: 'fake-salt:$password');
  }

  @override
  Future<bool> verify(
    String password, {
    required String expectedHash,
    required String salt,
  }) async {
    return expectedHash == 'fake-hash:$password' && salt == 'fake-salt:$password';
  }
}

class MockAuditRepository extends Mock implements AuditRepository {}

void main() {
  late MockAuditRepository auditRepository;
  late AppDatabase db;
  late AuthRepositoryImpl repository;

  setUp(() {
    auditRepository = MockAuditRepository();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = AuthRepositoryImpl(
      db: db,
      passwordHasher: _FakePasswordHasher(),
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
      await repository.createFirstOwner(
        username: 'chidinma',
        email: 'chidinma@example.com',
        fullName: 'Chidinma Okafor',
        password: 'correcthorse1',
      );
      expect(await repository.hasAnyOwnerAccount(), isTrue);
    });
  });

  group('createFirstOwner', () {
    test('creates the account, signs it in, and records BOOTSTRAP_ADMIN', () async {
      final user = await repository.createFirstOwner(
        username: 'chidinma',
        email: 'chidinma@example.com',
        fullName: 'Chidinma Okafor',
        password: 'correcthorse1',
      );

      expect(user.role, AuthRole.owner);
      expect(repository.currentUser?.username, 'chidinma');

      verify(() => auditRepository.log(
            action: 'BOOTSTRAP_ADMIN',
            module: 'AUTH',
            userId: user.id,
            recordId: user.id,
            details: {'created_username': 'chidinma'},
          )).called(1);
    });

    test('rejects a second call once an account already exists', () async {
      await repository.createFirstOwner(
        username: 'chidinma',
        email: 'chidinma@example.com',
        fullName: 'Chidinma Okafor',
        password: 'correcthorse1',
      );

      await expectLater(
        repository.createFirstOwner(
          username: 'ngozi',
          email: 'ngozi@example.com',
          fullName: 'Ngozi Eze',
          password: 'correcthorse2',
        ),
        throwsA(isA<BusinessRuleFailure>()),
      );
    });

    test('rejects a password shorter than 8 characters', () async {
      await expectLater(
        repository.createFirstOwner(
          username: 'chidinma',
          email: 'chidinma@example.com',
          fullName: 'Chidinma Okafor',
          password: 'short1',
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('rejects a duplicate username', () async {
      await repository.createFirstOwner(
        username: 'chidinma',
        email: 'chidinma@example.com',
        fullName: 'Chidinma Okafor',
        password: 'correcthorse1',
      );
      // Only reachable in practice via createAdditionalOwner, since
      // createFirstOwner itself is one-shot — exercised through it here
      // for the same reason isolated_backup_env-style tests hit a
      // shared helper directly rather than only through its one current
      // caller.
      await expectLater(
        repository.createAdditionalOwner(
          username: 'chidinma',
          email: 'different@example.com',
          fullName: 'Someone Else',
          password: 'correcthorse2',
        ),
        throwsA(isA<BusinessRuleFailure>()),
      );
    });
  });

  group('login', () {
    setUp(() async {
      await repository.createFirstOwner(
        username: 'chidinma',
        email: 'chidinma@example.com',
        fullName: 'Chidinma Okafor',
        password: 'correcthorse1',
      );
      await repository.logout();
      clearInteractions(auditRepository);
    });

    test('succeeds with the right credentials and records LOGIN', () async {
      final user = await repository.login(username: 'chidinma', password: 'correcthorse1');

      expect(user.username, 'chidinma');
      expect(repository.currentUser?.username, 'chidinma');
      verify(() => auditRepository.log(action: 'LOGIN', module: 'AUTH', userId: user.id))
          .called(1);
    });

    test('fails for an unknown username and records LOGIN_FAILED', () async {
      await expectLater(
        repository.login(username: 'nobody', password: 'whatever1'),
        throwsA(isA<AuthFailure>()),
      );
    });

    test(
        'BUG FIX regression test (self-audit pass): rejects a deactivated account '
        'even with the correct password, mirroring auth_service.py\'s is_active '
        'check exactly. There is no public method yet to deactivate an account '
        '(that arrives with a future Employees/access-revocation stage), so this '
        'writes directly to the table to simulate it — this is exactly the check '
        'that was missing entirely before this fix.', () async {
      await (db.update(db.users)..where((u) => u.username.equals('chidinma'))).write(
        const UsersCompanion(isActive: Value(false)),
      );

      await expectLater(
        repository.login(username: 'chidinma', password: 'correcthorse1'),
        throwsA(isA<AuthFailure>()),
      );
    });

    test('fails for the wrong password and records LOGIN_FAILED', () async {
      await expectLater(
        repository.login(username: 'chidinma', password: 'wrongpassword1'),
        throwsA(isA<AuthFailure>()),
      );
      verify(() => auditRepository.log(
            action: 'LOGIN_FAILED',
            module: 'AUTH',
            details: {'username': 'chidinma'},
          )).called(1);
    });

    test('locks the account after 5 failed attempts, mirroring auth_service.py exactly',
        () async {
      for (var i = 0; i < 5; i++) {
        await expectLater(
          repository.login(username: 'chidinma', password: 'wrongpassword1'),
          throwsA(isA<AuthFailure>()),
        );
      }

      // The 6th attempt — even with the CORRECT password — must now be
      // rejected as locked, not merely as another wrong-password
      // failure, since the account is locked before the password is
      // even checked (mirrors auth_service.py's own check order).
      await expectLater(
        repository.login(username: 'chidinma', password: 'correcthorse1'),
        throwsA(isA<AuthFailure>()),
      );
      verify(() => auditRepository.log(
            action: 'LOGIN_BLOCKED_LOCKOUT',
            module: 'AUTH',
            details: {'username': 'chidinma'},
          )).called(1);
    });

    test('a successful login resets a nonzero failed-attempt count', () async {
      await expectLater(
        repository.login(username: 'chidinma', password: 'wrongpassword1'),
        throwsA(isA<AuthFailure>()),
      );

      await repository.login(username: 'chidinma', password: 'correcthorse1');

      // Confirmed indirectly: 4 more wrong attempts (5 total since the
      // counter reset) must NOT lock the account, since a successful
      // login should have zeroed it back to 0 rather than leaving it at
      // 1 from the earlier failure.
      for (var i = 0; i < 4; i++) {
        await expectLater(
          repository.login(username: 'chidinma', password: 'wrongpassword1'),
          throwsA(isA<AuthFailure>()),
        );
      }
      final user = await repository.login(username: 'chidinma', password: 'correcthorse1');
      expect(user.username, 'chidinma'); // would have thrown accountLocked otherwise
    });
  });

  group('createAdditionalOwner', () {
    test('an already-signed-in owner can create a co-owner account', () async {
      await repository.createFirstOwner(
        username: 'chidinma',
        email: 'chidinma@example.com',
        fullName: 'Chidinma Okafor',
        password: 'correcthorse1',
      );

      final coOwner = await repository.createAdditionalOwner(
        username: 'ngozi',
        email: 'ngozi@example.com',
        fullName: 'Ngozi Eze',
        password: 'correcthorse2',
      );

      expect(coOwner.role, AuthRole.owner);
      // Does NOT sign the acting owner out — see AuthRepository's own
      // doc comment on why this differs from createFirstOwner.
      expect(repository.currentUser?.username, 'chidinma');
    });

    test('rejects the call when nobody is signed in', () async {
      await expectLater(
        repository.createAdditionalOwner(
          username: 'ngozi',
          email: 'ngozi@example.com',
          fullName: 'Ngozi Eze',
          password: 'correcthorse2',
        ),
        throwsA(isA<AuthFailure>()),
      );
    });
  });

  group('logout', () {
    test('clears the current user and restoreSession afterward returns null', () async {
      await repository.createFirstOwner(
        username: 'chidinma',
        email: 'chidinma@example.com',
        fullName: 'Chidinma Okafor',
        password: 'correcthorse1',
      );

      await repository.logout();

      expect(repository.currentUser, isNull);
      expect(await repository.restoreSession(), isNull);
    });
  });

  group('restoreSession', () {
    test('restores the signed-in user across a fresh repository instance', () async {
      final created = await repository.createFirstOwner(
        username: 'chidinma',
        email: 'chidinma@example.com',
        fullName: 'Chidinma Okafor',
        password: 'correcthorse1',
      );

      // A fresh instance over the SAME database, standing in for the
      // app restarting — the whole point of restoreSession existing.
      final restarted = AuthRepositoryImpl(
        db: db,
        passwordHasher: _FakePasswordHasher(),
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
      await repository.createFirstOwner(
        username: 'chidinma',
        email: 'chidinma@example.com',
        fullName: 'Chidinma Okafor',
        password: 'correcthorse1',
      );

      expect(await repository.getActiveLocationId(), isNull);
    });

    test('returns whatever was set', () async {
      await repository.createFirstOwner(
        username: 'chidinma',
        email: 'chidinma@example.com',
        fullName: 'Chidinma Okafor',
        password: 'correcthorse1',
      );

      await repository.setActiveLocationId('loc-1');

      expect(await repository.getActiveLocationId(), 'loc-1');
    });

    test('is a no-op with no active session', () async {
      // No createFirstOwner/login call in this test — nothing to
      // attach a location to, and this should not throw.
      await repository.setActiveLocationId('loc-1');
      expect(await repository.getActiveLocationId(), isNull);
    });

    test('survives a second sign-in over an existing session', () async {
      // NOT a logout()-then-login() cycle — logout() deletes the
      // Sessions row outright (_clearSession), so there is nothing left
      // to preserve across that specific path; this is the scenario
      // _persistSession's own doc comment actually describes: "a
      // different user signing in without an intervening clean logout
      // (app force-closed, etc)" — login() goes straight to
      // _persistSession with no _clearSession first, so the prior
      // session row (and its activeLocationId) is still there for the
      // new one to read and carry forward.
      await repository.createFirstOwner(
        username: 'chidinma',
        email: 'chidinma@example.com',
        fullName: 'Chidinma Okafor',
        password: 'correcthorse1',
      );
      await repository.setActiveLocationId('loc-1');

      await repository.login(username: 'chidinma', password: 'correcthorse1');

      expect(await repository.getActiveLocationId(), 'loc-1');
    });
  });
}
