import 'package:fulus_mobile/core/errors/failure.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/repositories/audit_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/auth_user.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late AuditRepositoryImpl repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = AuditRepositoryImpl(db: db);
  });

  tearDown(() async {
    await db.close();
  });

  group('log', () {
    test('writes an entry with the given fields', () async {
      await repository.log(
        userId: 'user-1',
        action: 'LOGIN',
        module: 'AUTH',
      );

      final entries = await repository.getAuditLogs(requestingRole: AuthRole.owner);
      expect(entries, hasLength(1));
      expect(entries.single.userId, 'user-1');
      expect(entries.single.action, 'LOGIN');
      expect(entries.single.module, 'AUTH');
    });

    test('accepts a null userId — anonymous/system events, e.g. LOGIN_FAILED for an '
        'unknown username, mirroring the backend column\'s own nullability', () async {
      await repository.log(action: 'LOGIN_FAILED', module: 'AUTH');

      final entries = await repository.getAuditLogs(requestingRole: AuthRole.owner);
      expect(entries.single.userId, isNull);
    });

    test('round-trips details as JSON', () async {
      await repository.log(
        userId: 'user-1',
        action: 'BOOTSTRAP_ADMIN',
        module: 'AUTH',
        recordId: 'user-1',
        details: {'created_username': 'chidinma'},
      );

      final entries = await repository.getAuditLogs(requestingRole: AuthRole.owner);
      expect(entries.single.recordId, 'user-1');
      expect(entries.single.details, {'created_username': 'chidinma'});
    });

    test('never throws, even if the underlying write would fail', () async {
      // Closing the database first, then logging to it, stands in for
      // "the write fails for some reason" without needing to fabricate
      // a more elaborate failure — mirrors audit_service.log's own
      // must-never-throw contract (verified directly against the
      // backend source).
      await db.close();
      await expectLater(
        repository.log(action: 'LOGIN', module: 'AUTH'),
        completes,
      );
    });
  });

  group('getAuditLogs', () {
    test('is owner-only, mirroring require_role(UserRole.ADMIN) on the backend exactly',
        () async {
      await repository.log(action: 'LOGIN', module: 'AUTH');

      await expectLater(
        repository.getAuditLogs(requestingRole: AuthRole.employee),
        throwsA(isA<AuthFailure>()),
      );
    });

    test('filters by module', () async {
      await repository.log(action: 'LOGIN', module: 'AUTH');
      await repository.log(action: 'CREATE', module: 'INVENTORY');

      final entries = await repository.getAuditLogs(
        requestingRole: AuthRole.owner,
        module: 'AUTH',
      );

      expect(entries, hasLength(1));
      expect(entries.single.module, 'AUTH');
    });

    test('filters by userId', () async {
      await repository.log(userId: 'user-1', action: 'LOGIN', module: 'AUTH');
      await repository.log(userId: 'user-2', action: 'LOGIN', module: 'AUTH');

      final entries = await repository.getAuditLogs(
        requestingRole: AuthRole.owner,
        userId: 'user-1',
      );

      expect(entries, hasLength(1));
      expect(entries.single.userId, 'user-1');
    });

    test('orders newest first', () async {
      await repository.log(action: 'FIRST', module: 'AUTH');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repository.log(action: 'SECOND', module: 'AUTH');

      final entries = await repository.getAuditLogs(requestingRole: AuthRole.owner);

      expect(entries.first.action, 'SECOND');
      expect(entries.last.action, 'FIRST');
    });

    test('paginates using page/pageSize', () async {
      for (var i = 0; i < 5; i++) {
        await repository.log(action: 'EVENT_$i', module: 'AUTH');
      }

      final firstPage = await repository.getAuditLogs(
        requestingRole: AuthRole.owner,
        page: 1,
        pageSize: 2,
      );
      final secondPage = await repository.getAuditLogs(
        requestingRole: AuthRole.owner,
        page: 2,
        pageSize: 2,
      );

      expect(firstPage, hasLength(2));
      expect(secondPage, hasLength(2));
      expect(firstPage.map((e) => e.action), isNot(containsAll(secondPage.map((e) => e.action))));
    });
  });
}
