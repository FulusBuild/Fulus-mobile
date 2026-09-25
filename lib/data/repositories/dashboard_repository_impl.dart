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
  /// [clock] exists for tests. getHeroState's dayStatus needs to know
  /// whether a shift closed "today" — see that method's comment — and
  /// DateTime.now() can't give a test a fixed instant to build fixtures
  /// against, only whatever moment CI happens to run at.
  DashboardRepositoryImpl({
    required AppDatabase db,
    DashboardEngine engine = const DashboardEngine(),
    DateTime Function() clock = DateTime.now,
  })  : _db = db,
        _engine = engine,
        _clock = clock;

  final AppDatabase _db;
  final DashboardEngine _engine;
  final DateTime Function() _clock;

  @override
  Future<HomeHeroState> getHeroState({
    required String currentAuthUserId,
    required bool isOwner,
    required String locationId,
  }) async {
    final now = _clock();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));

    // deletedAt.isNull() matters here specifically: sale_repository_impl
    // .dart's own sales queries always filter it (a void/return-voided
    // sale is soft-deleted, same as everywhere else in this app that
    // treats deletedAt as "gone"), but this method's todaySales/
    // yesterdaySales queries didn't — a voided sale was still being
    // counted into Home's own hero totals even though every other
    // sales-total view in the app already excludes it. Fixed here
    // rather than left as a pre-existing gap: it's a real correctness
    // bug in the exact query Roles & Permissions' Home-dashboard review
    // was checking, not a new one introduced by that work.
    // Bug fix (employee data isolation): currentAuthUserId was already
    // a parameter here, and Permission.viewDashboardStats' own doc
    // comment already states the intended policy — "an employee's Home
    // is their own shift, full stop" (Decision 13) — but this query
    // never actually applied it: every signed-in user saw the same
    // whole-business today's-total regardless of who they were. Scoped
    // to the caller's own sales unless they can see business-wide
    // (owner, or granted viewDashboardStats — home_screen.dart's
    // `showBusinessWide` computes the same thing for isOwner already;
    // this just finally consults it for the query too).
    final todaySalesQuery = _db.select(_db.sales)
      ..where((s) => s.saleDate.isBiggerOrEqualValue(todayStart) & s.locationId.equals(locationId) & s.deletedAt.isNull());
    if (!isOwner) {
      todaySalesQuery.where((s) => s.cashierUserId.equals(currentAuthUserId));
    }
    final todaySales = await todaySalesQuery.get();
    final todayTotal = todaySales.fold<double>(0, (s, r) => s + r.total);

    double yesterdayTotal = 0;
    int yesterdayCount = 0;
    if (isOwner) {
      final yesterdaySales = await (_db.select(_db.sales)
            ..where((s) =>
                s.saleDate.isBiggerOrEqualValue(yesterdayStart) &
                s.saleDate.isSmallerThanValue(todayStart) &
                s.locationId.equals(locationId) &
                s.deletedAt.isNull()))
          .get();
      yesterdayTotal = yesterdaySales.fold<double>(0, (s, r) => s + r.total);
      yesterdayCount = yesterdaySales.length;
    }

    // The Screen Gallery mockup (Volume 4, Home · All States) settles
    // what the two earlier attempts here got wrong: Closed is
    // deliberately button-less — "a quieter treatment... the
    // difference between a total still moving and one that's now
    // history" — and Kwame's employee view has "no Open/Close Shop...
    // at all, not hidden, structurally absent" either. So ClosedHero
    // must never carry a button (reverted from home_screen.dart; see
    // that file's comment); reachability on a new day has to come from
    // dayStatus itself resolving back to notYetOpened, which is also
    // what "Before opening"'s "Yesterday: X" framing assumes exists in
    // the first place.
    //
    // So: `open` iff a shift is currently open. Otherwise `closed` if
    // the most recently closed shift closed today, or if no shift ever
    // existed (dashboard_repository_impl_test.dart's zero-history case
    // expects `closed`, not a "Ready to open?" prompt with no real
    // yesterday to show); `notYetOpened` if the last close was on an
    // earlier day, which is what actually gives Home its Open Shop
    // button back.
    //
    // This exact three-way split was tried once already and reverted:
    // it compared closedAt to todayStart using DateTime.now() directly,
    // and broke on a real CI run — a shift closed shortly before
    // midnight and checked shortly after rolled over to "yesterday" and
    // flipped the result (that run started ~00:08 UTC). [_clock] fixes
    // that at the root instead of routing around it: tests inject a
    // fixed instant and build fixtures against it, so this comparison
    // is deterministic instead of failing in roughly the one hour out
    // of twenty-four when CI happens to run right after local midnight.
    //
    // All location-scoped dashboard queries above are explicitly bound
    // to the active location. Business-wide permissions affect whose
    // sales are visible within that location, not which location is used.
    final openShift = await (_db.select(_db.cashDrawerShifts)
          ..where((s) => s.closedAt.isNull() & s.locationId.equals(locationId))
          ..limit(1))
        .getSingleOrNull();

    final ShopDayStatus dayStatus;
    if (openShift != null) {
      dayStatus = ShopDayStatus.open;
    } else {
      final lastClosedShift = await (_db.select(_db.cashDrawerShifts)
            ..where((s) => s.closedAt.isNotNull() & s.locationId.equals(locationId))
            ..orderBy([(s) => OrderingTerm.desc(s.closedAt)])
            ..limit(1))
          .getSingleOrNull();
      if (lastClosedShift == null) {
        dayStatus = ShopDayStatus.closed;
      } else {
        final closedToday = !lastClosedShift.closedAt!.isBefore(todayStart);
        dayStatus = closedToday ? ShopDayStatus.closed : ShopDayStatus.notYetOpened;
      }
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
  Future<SecondaryNoticeSelection> getSecondaryNotices({required String locationId, int max = 2}) async {
    final products = await (_db.select(_db.products)..where((p) => p.isActive.equals(true))).get();
    final stockLevels = await (_db.select(_db.productStockLevels)..where((s) => s.locationLocalId.equals(locationId))).get();
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
