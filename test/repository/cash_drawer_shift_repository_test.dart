import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/repositories/cash_drawer_shift_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/auth_user.dart';
import 'package:fulus_mobile/domain/entities/cash_drawer_shift.dart';
import 'package:fulus_mobile/domain/repositories/auth_repository.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_seed_helpers.dart';

/// Hand-rolled, not a mocking-library Mock — matches the pattern already
/// used in sale_repository_test.dart / draft_cart_repository_test.dart.
/// The only member this repository reads is [currentUser].
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this.currentUser);

  @override
  final AuthUser? currentUser;
  @override
  Future<bool> hasAnyOwnerAccount() async => throw UnimplementedError();
  @override
  Future<AuthUser?> restoreSession() async => throw UnimplementedError();
  @override
  Future<AuthUser> createFirstOwner({
    required String username,
    required String email,
    required String fullName,
    required String password,
  }) async =>
      throw UnimplementedError();
  @override
  Future<AuthUser> login({required String username, required String password}) async =>
      throw UnimplementedError();
  @override
  Future<AuthUser> createAdditionalOwner({
    required String username,
    required String email,
    required String fullName,
    required String password,
  }) async =>
      throw UnimplementedError();
  @override
  Future<AuthUser> createEmployeeAccount({
    required String employeeId,
    required String username,
    required String email,
    required String password,
  }) async =>
      throw UnimplementedError();
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
        ),
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

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

    test('rejects opening a second shift while one is already active',
        () async {
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

    // Regression test for a confirmed bug (audit finding, Technical Debt
    // #5): the "is one already open" check and the insert that opens a
    // new one used to be two separate calls, not one transaction — a
    // rapid double-tap on "Open Shop" could have both calls see no
    // active shift before either insert landed, opening two concurrent
    // shifts for the same location. openShift now wraps both steps in
    // one _db.transaction(), which Drift serializes on a single
    // connection: the second call's check can't run until the first
    // call's transaction has fully committed.
    test(
        'regression: two near-simultaneous opens for the same location '
        'never both succeed', () async {
      const draft = CashDrawerShiftDraft(locationId: locationId, openingCash: 5000);

      // Both calls start here, before either has a chance to complete —
      // this is what actually exercises the race, not just calling
      // openShift twice in sequence.
      final first = repository.openShift(draft).then<Object?>((s) => s).catchError((e) => e);
      final second = repository.openShift(draft).then<Object?>((s) => s).catchError((e) => e);
      final results = await Future.wait([first, second]);

      final succeeded = results.whereType<CashDrawerShift>();
      final failed = results.whereType<StateError>();
      expect(succeeded, hasLength(1),
          reason: 'exactly one of the two concurrent opens should win');
      expect(failed, hasLength(1));

      final openRows = await (db.select(db.cashDrawerShifts)
            ..where(
              (s) => s.locationId.equals(locationId) & s.closedAt.isNull(),
            ))
          .get();
      expect(openRows, hasLength(1));
    });
  });

  group('closeShift', () {
    test('computes the cash difference against expected cash', () async {
      final shift = await repository.openShift(
        const CashDrawerShiftDraft(locationId: locationId, openingCash: 5000),
      );

      // No sales/expenses recorded, so expected cash is just the
      // opening float — closing with 200 more than that should record
      // a +200 difference.
      final closed = await repository.closeShift(
        shiftLocalId: shift.localId,
        closingCash: 5200,
      );

      expect(closed.closingCash, 5200);
      expect(closed.cashDifference, 200);
      expect(closed.closedAt, isNotNull);
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

    // Same reasoning and same fix shape as the openShift regression
    // test above, applied to closeShift's own check-then-act pair.
    test(
        'regression: two near-simultaneous closes for the same shift '
        'never both succeed', () async {
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

      final succeeded = results.whereType<CashDrawerShift>();
      final failed = results.whereType<StateError>();
      expect(succeeded, hasLength(1),
          reason: 'exactly one of the two concurrent closes should win');
      expect(failed, hasLength(1));
    });
  });
}
