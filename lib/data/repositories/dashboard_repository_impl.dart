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

    // Simple binary: `open` iff a shift is currently open (closedAt
    // null), `closed` otherwise — no shift ever, or the most recent one
    // is already closed, regardless of when. A prior version tried a
    // third path back to `notYetOpened` once the last closed shift
    // wasn't from today (so Home would get its Open Shop button back on
    // a new calendar day), comparing closedAt against todayStart. That
    // broke two ways, both caught by dashboard_repository_impl_test.dart:
    // a location with zero shift history ever read as `notYetOpened`
    // when the tests require `closed` for that case, and the
    // today-vs-earlier comparison was wall-clock-dependent — a shift
    // closed shortly before midnight and checked shortly after rolled
    // over to "yesterday" and flipped the result, which is exactly what
    // happened in the CI run this fixes (test ran ~00:08 UTC).
    // Trade-off worth knowing: ClosedHero has no Open Shop button (see
    // home_screen.dart), and DailyClosingCountScreen is only reachable
    // from OpenHero's Close Shop action, so once a shift closes, Home
    // has no path back to Open Shop until dayStatus has a real source
    // (Volume 8's Daily Closing, Stage 8 — see dashboard_engine.dart's
    // ShopDayStatus doc comment) or that gap gets closed some other
    // way. Still not location-scoped — same as todaySales/yesterdaySales
    // above, neither of which filter by location either; Home has no
    // location context to filter by until a location switcher exists
    // (Phase 2).
    final openShift = await (_db.select(_db.cashDrawerShifts)
          ..where((s) => s.closedAt.isNull())
          ..limit(1))
        .getSingleOrNull();
    final dayStatus = openShift != null ? ShopDayStatus.open : ShopDayStatus.closed;

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
