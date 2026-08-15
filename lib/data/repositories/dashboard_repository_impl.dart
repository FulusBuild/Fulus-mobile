import 'package:drift/drift.dart';

import '../../domain/entities/dashboard_summary.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../../domain/usecases/dashboard_engine.dart';
import '../local/database/database.dart';

/// Same integration posture as receipt/reports_repository_impl.dart —
/// see those files' header comments. This is the one place Home's data
/// touches Sales/Products/ProductStockLevels/Customers/SyncQueue
/// directly.
class DashboardRepositoryImpl implements DashboardRepository {
  DashboardRepositoryImpl({
    required AppDatabase db,
    DashboardEngine engine = const DashboardEngine(),
  })  : _db = db,
        _engine = engine;

  final AppDatabase _db;
  final DashboardEngine _engine;

  @override
  Future<HomeHeroState> getHeroState({
    required String currentAuthUserId,
    required bool isOwner,
  }) async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));

    final todaySales = await (_db.select(_db.sales)..where((s) => s.saleDate.isBiggerOrEqualValue(todayStart))).get();
    final todayTotal = todaySales.fold<double>(0, (s, r) => s + r.total);

    double yesterdayTotal = 0;
    int yesterdayCount = 0;
    if (isOwner) {
      final yesterdaySales = await (_db.select(_db.sales)
            ..where((s) =>
                s.saleDate.isBiggerOrEqualValue(yesterdayStart) & s.saleDate.isSmallerThanValue(todayStart)))
          .get();
      yesterdayTotal = yesterdaySales.fold<double>(0, (s, r) => s + r.total);
      yesterdayCount = yesterdaySales.length;
    }

    // Bug fix: this used to be a hard binary (`open` if a shift is
    // currently open, `closed` otherwise) with no way back to
    // notYetOpened once ANY shift had ever been closed — Home's Open
    // Shop button only renders for NotYetOpenedHero (see
    // home_screen.dart), and ClosedHero has no button at all, so once a
    // shop closed once, Home was permanently stuck on "Today (Closed)"
    // with no way to open again, even the next calendar day. A day now
    // only reads as `closed` if the most recently CLOSED shift closed
    // today; closed on any earlier day (or no shift ever existed) reads
    // as `notYetOpened` instead. Still not location-scoped — same as
    // todaySales/yesterdaySales above, neither of which filter by
    // location either; Home has no location context to filter by until
    // a location switcher exists (Phase 2).
    final openShift = await (_db.select(_db.cashDrawerShifts)
          ..where((s) => s.closedAt.isNull())
          ..limit(1))
        .getSingleOrNull();

    final ShopDayStatus dayStatus;
    if (openShift != null) {
      dayStatus = ShopDayStatus.open;
    } else {
      final lastClosedShift = await (_db.select(_db.cashDrawerShifts)
            ..where((s) => s.closedAt.isNotNull())
            ..orderBy([(s) => OrderingTerm.desc(s.closedAt)])
            ..limit(1))
          .getSingleOrNull();
      final closedToday = lastClosedShift != null && !lastClosedShift.closedAt!.isBefore(todayStart);
      dayStatus = closedToday ? ShopDayStatus.closed : ShopDayStatus.notYetOpened;
    }

    return _engine.deriveHeroState(
      isOwner: isOwner,
      shiftOrTodayTotal: todayTotal,
      shiftOrTodaySalesCount: todaySales.length,
      dayStatus: dayStatus,
      yesterdayTotal: yesterdayTotal,
      yesterdaySalesCount: yesterdayCount,
      now: now,
    );
  }

  @override
  Future<SecondaryNoticeSelection> getSecondaryNotices({int max = 2}) async {
    final products = await (_db.select(_db.products)..where((p) => p.isActive.equals(true))).get();
    final stockLevels = await _db.select(_db.productStockLevels).get();
    final stockByProduct = <String, int>{};
    for (final level in stockLevels) {
      stockByProduct[level.productLocalId] = (stockByProduct[level.productLocalId] ?? 0) + level.currentStock;
    }
    final lowStockCount = products.where((p) {
      final stock = stockByProduct[p.localId] ?? 0;
      return stock > 0 && stock <= p.lowStockThreshold;
    }).length;

    final customers = await (_db.select(_db.customers)..where((c) => c.deletedAt.isNull())).get();
    final pendingCredit = customers.fold<double>(0, (s, c) => s + c.outstandingBalance);

    // Real count now — SyncQueueItems is exactly "work not yet synced,"
    // one row per queued create/update/delete (SyncQueue, sync_queue.dart),
    // removed once it settles. The earlier placeholder's own comment
    // was about a genuinely different, pre-offline-pivot queue that no
    // longer exists in this schema; this one is current.
    final unsyncedCount = (await _db.select(_db.syncQueueItems).get()).length;

    final candidates = [
      SecondaryNotice(type: SecondaryNoticeType.lowStock, label: 'Low stock', value: lowStockCount),
      SecondaryNotice(type: SecondaryNoticeType.pendingCredit, label: 'Pending credit', value: pendingCredit),
      SecondaryNotice(type: SecondaryNoticeType.unsyncedItems, label: 'Unsynced', value: unsyncedCount),
    ];
    return _engine.selectSecondaryNotices(candidates, max: max);
  }
}
