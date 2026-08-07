import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:fulus_mobile/data/repositories/dashboard_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/dashboard_summary.dart';
import 'package:fulus_mobile/domain/usecases/dashboard_engine.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// **Phase 0 completion pass.** No test existed for this repository
/// before this pass — it's included here specifically because this
/// pass changed two previously-hardcoded values (dayStatus,
/// unsyncedCount) to real queries, and "verify every fix" means this
/// file needs its first real test, not just the fix itself.
void main() {
  late AppDatabase db;
  late DashboardRepositoryImpl repository;

  const locationId = 'loc-1';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = DashboardRepositoryImpl(db: db);
    await db.into(db.locations).insert(LocationsCompanion.insert(
          localId: locationId,
          name: 'Main Store',
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          syncStatus: SyncStatus.settled,
        ));
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedSale({required double total, DateTime? saleDate}) {
    final id = 'sale-${DateTime.now().microsecondsSinceEpoch}-${total.toString()}';
    return db.into(db.sales).insert(SalesCompanion.insert(
          localId: id,
          clientReference: id,
          locationId: locationId,
          saleDate: saleDate ?? DateTime.now(),
          subtotal: total,
          total: total,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          syncStatus: SyncStatus.settled,
        ));
  }

  group('getHeroState — day status', () {
    test('reports the day closed when no cash drawer shift is open', () async {
      final state = await repository.getHeroState(currentAuthUserId: 'u1', isOwner: true);
      expect(state, isA<ClosedHero>());
    });

    test('reports the day open when a cash drawer shift has no closedAt', () async {
      await db.into(db.cashDrawerShifts).insert(CashDrawerShiftsCompanion.insert(
            localId: 'shift-1',
            cashierUserId: 'u1',
            locationId: locationId,
            openedAt: DateTime.now().subtract(const Duration(hours: 2)),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            syncStatus: SyncStatus.settled,
          ));

      final state = await repository.getHeroState(currentAuthUserId: 'u1', isOwner: true);

      expect(state, isA<OpenHero>());
    });

    test('a shift that has already been closed does not count as the day being open', () async {
      await db.into(db.cashDrawerShifts).insert(CashDrawerShiftsCompanion.insert(
            localId: 'shift-1',
            cashierUserId: 'u1',
            locationId: locationId,
            openedAt: DateTime.now().subtract(const Duration(hours: 5)),
            closedAt: Value(DateTime.now().subtract(const Duration(hours: 1))),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            syncStatus: SyncStatus.settled,
          ));

      final state = await repository.getHeroState(currentAuthUserId: 'u1', isOwner: true);

      expect(state, isA<ClosedHero>());
    });

    test('an employee always sees their own shift, regardless of day status', () async {
      final state = await repository.getHeroState(currentAuthUserId: 'u1', isOwner: false);
      expect(state, isA<EmployeeShiftHero>());
    });
  });

  group('getHeroState — sales totals', () {
    test('todayTotal reflects only sales from today', () async {
      await seedSale(total: 500);
      await seedSale(total: 300, saleDate: DateTime.now().subtract(const Duration(days: 3)));

      final state = await repository.getHeroState(currentAuthUserId: 'u1', isOwner: true) as ClosedHero;

      expect(state.finalTotal, 500);
      expect(state.finalSalesCount, 1);
    });
  });

  group('getSecondaryNotices — unsyncedCount', () {
    test('reflects the real number of items still in the sync queue', () async {
      for (var i = 0; i < 3; i++) {
        await db.into(db.syncQueueItems).insert(SyncQueueItemsCompanion.insert(
              id: 'q$i',
              entityType: 'product',
              entityLocalId: 'p$i',
              operation: 'create',
              priority: 1,
              enqueuedAt: DateTime.now(),
            ));
      }

      final selection = await repository.getSecondaryNotices();

      final unsynced = selection.shown.where((n) => n.type == SecondaryNoticeType.unsyncedItems);
      expect(unsynced.single.value, 3);
    });

    test('an empty sync queue produces no unsynced notice at all', () async {
      final selection = await repository.getSecondaryNotices();
      expect(selection.shown.where((n) => n.type == SecondaryNoticeType.unsyncedItems), isEmpty);
    });
  });
}
