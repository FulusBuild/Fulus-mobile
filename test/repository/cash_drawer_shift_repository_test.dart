import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/repositories/cash_drawer_shift_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/auth_user.dart';
import 'package:fulus_mobile/domain/entities/cash_drawer_shift.dart';
import 'package:fulus_mobile/domain/repositories/auth_repository.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_seed_helpers.dart';

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this.currentUser);

  @override
  final AuthUser? currentUser;
  @override
  Future<bool> hasAnyOwnerAccount() async => throw UnimplementedError();
  @override
  Future<AuthUser?> restoreSession() async => throw UnimplementedError();
  @override
  Future<AuthUser> createFirstOwner({required String fullName}) async => throw UnimplementedError();
  @override
  Future<void> setOwnLoginPin({required String pin}) async => throw UnimplementedError();
  @override
  Future<List<AuthUser>> listLocalIdentities() async => throw UnimplementedError();
  @override
  Future<AuthUser> switchLocalUser({required String userId, String? pin}) async => throw UnimplementedError();
  @override
  Future<AuthUser> createAdditionalOwner({required String fullName, required String pin}) async => throw UnimplementedError();
  @override
  Future<AuthUser> createEmployeeAccount({required String employeeId, required String pin, AuthRole role = AuthRole.employee}) async => throw UnimplementedError();
  @override
  Future<void> logout() async => throw UnimplementedError();
  @override
  Future<String?> getActiveLocationId() async => throw UnimplementedError();
  @override
  Future<void> setActiveLocationId(String locationId) async => throw UnimplementedError();
}

void main() {
  late AppDatabase db;
  late CashDrawerShiftRepositoryImpl repository;

  const locationId = 'loc-1';
  const cashierUserId = 'user-cashier-1';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedLocation(db, localId: locationId);
    await seedUser(db, localId: cashierUserId);
    repository = CashDrawerShiftRepositoryImpl(
      db: db,
      syncQueue: SyncQueue(db),
      authRepository: _FakeAuthRepository(
        const AuthUser(
          id: cashierUserId,
          username: 'cashier1',
          email: 'cashier1@test.local',
          fullName: 'Test Cashier',
          role: AuthRole.employee,
          isActive: true,
          hasLoginPin: true,
        ),
      ),
    );
  });

  tearDown(() async => db.close());

  group('openShift', () {
    test('opens a shift with the given opening cash', () async {
      final shift = await repository.openShift(
        const CashDrawerShiftDraft(locationId: locationId, openingCash: 5000),
      );
      expect(shift.openingCash, 5000);
      expect(shift.locationId, locationId);
      expect(shift.cashierUserId, cashierUserId);
      final active = await repository.getActiveShift(locationId: locationId);
      expect(active?.localId, shift.localId);
    });

    test('rejects negative opening cash', () async {
      await expectLater(
        repository.openShift(
          const CashDrawerShiftDraft(locationId: locationId, openingCash: -1),
        ),
        throwsArgumentError,
      );
    });

    test('rejects opening a second shift while one is already active', () async {
      await repository.openShift(
        const CashDrawerShiftDraft(locationId: locationId, openingCash: 5000),
      );
      await expectLater(
        repository.openShift(
          const CashDrawerShiftDraft(locationId: locationId, openingCash: 3000),
        ),
        throwsStateError,
      );
    });

    test('regression: two near-simultaneous opens for the same location never both succeed', () async {
      const draft = CashDrawerShiftDraft(locationId: locationId, openingCash: 5000);
      final first = repository.openShift(draft).then<Object?>((s) => s).catchError((e) => e);
      final second = repository.openShift(draft).then<Object?>((s) => s).catchError((e) => e);
      final results = await Future.wait([first, second]);
      expect(results.whereType<CashDrawerShift>(), hasLength(1));
      expect(results.whereType<StateError>(), hasLength(1));
      final openRows = await (db.select(db.cashDrawerShifts)
            ..where((s) => s.locationId.equals(locationId) & s.closedAt.isNull()))
          .get();
      expect(openRows, hasLength(1));
    });
  });

  group('closeShift', () {
    test('computes the cash difference against expected cash', () async {
      final shift = await repository.openShift(
        const CashDrawerShiftDraft(locationId: locationId, openingCash: 5000),
      );
      final closed = await repository.closeShift(
        shiftLocalId: shift.localId,
        closingCash: 5200,
      );
      expect(closed.closingCash, 5200);
      expect(closed.cashDifference, 200);
      expect(closed.closedAt, isNotNull);
      expect(closed.closingSummaryLocked, isTrue);
    });

    test('rejects negative closing cash before touching the shift', () async {
      final shift = await repository.openShift(
        const CashDrawerShiftDraft(locationId: locationId, openingCash: 5000),
      );
      await expectLater(
        repository.closeShift(shiftLocalId: shift.localId, closingCash: -1),
        throwsArgumentError,
      );
      final active = await repository.getActiveShift(locationId: locationId);
      expect(active?.isOpen, isTrue);
    });

    test('rejects closing a shift that is already closed', () async {
      final shift = await repository.openShift(
        const CashDrawerShiftDraft(locationId: locationId, openingCash: 5000),
      );
      await repository.closeShift(shiftLocalId: shift.localId, closingCash: 5000);
      await expectLater(
        repository.closeShift(shiftLocalId: shift.localId, closingCash: 5000),
        throwsStateError,
      );
    });

    test('persists the closing note and queues the close for offline sync', () async {
      final shift = await repository.openShift(
        const CashDrawerShiftDraft(locationId: locationId, openingCash: 5000),
      );
      await repository.closeShift(
        shiftLocalId: shift.localId,
        closingCash: 4975,
        notes: 'Short by 25 after recount',
      );

      final persisted = await repository.getShiftById(shift.localId);
      expect(persisted?.closingNote, 'Short by 25 after recount');
      expect(persisted?.closingSummaryLocked, isTrue);
      expect(persisted?.cashDifference, -25);

      final queue = await (db.select(db.syncQueueItems)
            ..where((q) => q.entityType.equals('cash_drawer_shift'))
            ..orderBy([(q) => OrderingTerm.asc(q.enqueuedAt)]))
          .get();
      expect(queue, hasLength(2));
      expect(queue.first.operation, 'create');
      expect(queue.last.operation, 'close');
      expect(queue.first.priority, SyncPriority.salesAndPayments);
      expect(queue.last.priority, SyncPriority.salesAndPayments);
    });

    test('regression: two near-simultaneous closes for the same shift never both succeed', () async {
      final shift = await repository.openShift(
        const CashDrawerShiftDraft(locationId: locationId, openingCash: 5000),
      );
      final first = repository
          .closeShift(shiftLocalId: shift.localId, closingCash: 5000)
          .then<Object?>((s) => s)
          .catchError((e) => e);
      final second = repository
          .closeShift(shiftLocalId: shift.localId, closingCash: 5100)
          .then<Object?>((s) => s)
          .catchError((e) => e);
      final results = await Future.wait([first, second]);
      expect(results.whereType<CashDrawerShift>(), hasLength(1));
      expect(results.whereType<StateError>(), hasLength(1));
    });
    test('does not park an old rejection when a newer close is queued', () async {
      final shift = await repository.openShift(
        const CashDrawerShiftDraft(locationId: locationId, openingCash: 5000),
      );
      final queue = await (db.select(db.syncQueueItems)
            ..where((q) => q.entityType.equals('cash_drawer_shift'))
            ..where((q) => q.entityLocalId.equals(shift.localId)))
          .get();
      final old = queue.single;

      await db.into(db.syncQueueItems).insert(SyncQueueItemsCompanion.insert(
        id: 'new-close', entityType: 'cash_drawer_shift', entityLocalId: shift.localId,
        operation: 'close', priority: old.priority,
        enqueuedAt: old.enqueuedAt.add(const Duration(seconds: 1)),
      ));

      await repository.markAttentionNeeded(shift.localId, operationId: old.id);

      final row = await (db.select(db.cashDrawerShifts)
            ..where((s) => s.localId.equals(shift.localId)))
          .getSingle();
      expect(row.syncStatus, SyncStatus.pending);
    });

  });
}
