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
}
