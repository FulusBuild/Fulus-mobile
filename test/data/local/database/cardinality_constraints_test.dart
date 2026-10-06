import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test('allows at most one draft cart per location', () async {
    await db.into(db.locations).insert(LocationsCompanion.insert(
      localId: 'location-1',
      name: 'Main',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      syncStatus: SyncStatus.settled,
    ));

    await db.into(db.draftCarts).insert(DraftCartsCompanion.insert(
      localId: 'cart-1',
      locationId: 'location-1',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    ));

    await expectLater(
      db.into(db.draftCarts).insert(DraftCartsCompanion.insert(
        localId: 'cart-2',
        locationId: 'location-1',
        createdAt: DateTime(2026, 1, 2),
        updatedAt: DateTime(2026, 1, 2),
      )),
      throwsA(anything),
    );
  });

  test('allows closed shifts but only one open shift per location', () async {
    await db.into(db.locations).insert(LocationsCompanion.insert(
      localId: 'location-1',
      name: 'Main',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      syncStatus: SyncStatus.settled,
    ));

    await db.into(db.cashDrawerShifts).insert(CashDrawerShiftsCompanion.insert(
      localId: 'shift-1',
      serverId: const Value(null),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      syncStatus: SyncStatus.settled,
      cashierUserId: 'user-1',
      locationId: 'location-1',
      openedAt: DateTime(2026, 1, 1, 8),
      closedAt: const Value(null),
    ));

    await expectLater(
      db.into(db.cashDrawerShifts).insert(CashDrawerShiftsCompanion.insert(
        localId: 'shift-2',
        serverId: const Value(null),
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        syncStatus: SyncStatus.settled,
        cashierUserId: 'user-2',
        locationId: 'location-1',
        openedAt: DateTime(2026, 1, 1, 9),
        closedAt: const Value(null),
      )),
      throwsA(anything),
    );

    await db.into(db.cashDrawerShifts).insert(CashDrawerShiftsCompanion.insert(
      localId: 'shift-2',
      serverId: const Value(null),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      syncStatus: SyncStatus.settled,
      cashierUserId: 'user-2',
      locationId: 'location-1',
      openedAt: DateTime(2026, 1, 1, 9),
      closedAt: Value(DateTime(2026, 1, 1, 10)),
    ));
  });

  test('concurrent draft-cart creation cannot create two rows', () async {
    await db.into(db.locations).insert(LocationsCompanion.insert(
      localId: 'location-2',
      name: 'Second',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      syncStatus: SyncStatus.settled,
    ));

    final attempts = await Future.wait([
      db.into(db.draftCarts).insert(DraftCartsCompanion.insert(
        localId: 'cart-concurrent-1',
        locationId: 'location-2',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      )).then((_) => true).catchError((_) => false),
      db.into(db.draftCarts).insert(DraftCartsCompanion.insert(
        localId: 'cart-concurrent-2',
        locationId: 'location-2',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      )).then((_) => true).catchError((_) => false),
    ]);

    expect(attempts.where((accepted) => accepted).length, 1);
    expect(
      await (db.select(db.draftCarts)
            ..where((row) => row.locationId.equals('location-2')))
          .get(),
      hasLength(1),
    );
  });

  test('concurrent open-shift creation cannot create two active rows', () async {
    await db.into(db.locations).insert(LocationsCompanion.insert(
      localId: 'location-3',
      name: 'Third',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      syncStatus: SyncStatus.settled,
    ));

    Future<bool> openShift(String id, String cashier) {
      return db.into(db.cashDrawerShifts).insert(
        CashDrawerShiftsCompanion.insert(
          localId: id,
          serverId: const Value(null),
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          syncStatus: SyncStatus.settled,
          cashierUserId: cashier,
          locationId: 'location-3',
          openedAt: DateTime(2026, 1, 1, 8),
          closedAt: const Value(null),
        ),
      ).then((_) => true).catchError((_) => false);
    }

    final attempts = await Future.wait([
      openShift('shift-concurrent-1', 'user-1'),
      openShift('shift-concurrent-2', 'user-2'),
    ]);

    expect(attempts.where((accepted) => accepted).length, 1);
    expect(
      await (db.select(db.cashDrawerShifts)
            ..where((row) =>
                row.locationId.equals('location-3') &
                row.closedAt.isNull()))
          .get(),
      hasLength(1),
    );
  });

}
