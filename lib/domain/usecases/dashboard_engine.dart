import '../entities/dashboard_summary.dart';

/// Whether the business day has been opened/closed for cash-drawer
/// purposes. This concept is genuinely owned by Volume 8's Daily
/// Closing flow (Finance, Stage 8) — not yet built at the time this
/// module was written. Rather than block Stage 12 on Stage 8, or guess
/// at day-open/closed from sales activity alone (which Volume 4 never
/// describes as the actual rule — it's tied to an explicit Open Shop /
/// Close Shop action), this engine takes [ShopDayStatus] as a plain
/// input with [open] as the sensible default when no real day-status
/// source exists yet. DashboardRepositoryImpl is the integration seam:
/// once Stage 8 exposes real day-status data, only its call into
/// [DashboardEngine.deriveHeroState] needs to pass the real value —
/// this engine's logic already handles all three correctly.
enum ShopDayStatus { notYetOpened, open, closed }

/// Stage 12's pure-logic layer for Home. See dashboard_summary.dart's
/// class docs for why the five prose-described moments in Volume 4
/// collapse to three [HomeHeroState] variants plus the employee one.
class DashboardEngine {
  const DashboardEngine();

  /// The single entry point Home's screen calls. [isOwner] and
  /// [currentAuthUserId] come from Stage 2's session (this engine takes
  /// them as plain parameters rather than reading a session object
  /// itself, keeping it dependency-free); everything else is whatever
  /// DashboardRepositoryImpl already fetched.
  HomeHeroState deriveHeroState({
    required bool isOwner,
    required double shiftOrTodayTotal,
    required int shiftOrTodaySalesCount,
    required ShopDayStatus dayStatus,
    double yesterdayTotal = 0,
    int yesterdaySalesCount = 0,
    DateTime? now,
    int typicalClosingHour = 20,
  }) {
    // Decision 13: an employee's Home is their own shift, full stop —
    // never the business total, never the Open/Close Shop controls.
    if (!isOwner) {
      return EmployeeShiftHero(
        shiftTotal: shiftOrTodayTotal,
        shiftSalesCount: shiftOrTodaySalesCount,
      );
    }

    switch (dayStatus) {
      case ShopDayStatus.notYetOpened:
        return NotYetOpenedHero(
          yesterdayTotal: yesterdayTotal,
          yesterdaySalesCount: yesterdaySalesCount,
        );
      case ShopDayStatus.closed:
        return ClosedHero(
          finalTotal: shiftOrTodayTotal,
          finalSalesCount: shiftOrTodaySalesCount,
        );
      case ShopDayStatus.open:
        final hour = (now ?? DateTime.now()).hour;
        return OpenHero(
          todayTotal: shiftOrTodayTotal,
          todaySalesCount: shiftOrTodaySalesCount,
          closeShopEmphasized: hour >= typicalClosingHour,
          yesterdayTotal: yesterdayTotal,
          yesterdaySalesCount: yesterdaySalesCount,
        );
    }
  }

  /// Decision 12's hard cap: Home ever shows at most two notices at
  /// once, the two most operationally urgent, with a plain count of
  /// however many more genuinely exist. The cap is enforced here even
  /// when a caller requests a larger value, so presentation code cannot
  /// accidentally turn an operational summary into a dashboard wall of
  /// alerts.
  ///
  /// Priority order (most to least urgent): low stock (blocks selling),
  /// pending credit (money already owed needs chasing), unsynced items
  /// (technical state, lowest urgency). Within the same type, higher
  /// [SecondaryNotice.value] sorts first.
  SecondaryNoticeSelection selectSecondaryNotices(List<SecondaryNotice> candidates, {int max = 2}) {
    const priority = {
      SecondaryNoticeType.lowStock: 0,
      SecondaryNoticeType.pendingCredit: 1,
      SecondaryNoticeType.unsyncedItems: 2,
    };
    final meaningful = candidates.where((c) => c.value != 0).toList()
      ..sort((a, b) {
        final byType = priority[a.type]!.compareTo(priority[b.type]!);
        if (byType != 0) return byType;
        return b.value.compareTo(a.value);
      });

    // The product contract is intentionally stricter than the method's
    // convenience parameter: a caller may ask for fewer than two, but
    // never more than two. Negative values also degrade safely to zero.
    final effectiveMax = max.clamp(0, 2);
    if (meaningful.length <= effectiveMax) {
      return SecondaryNoticeSelection(shown: meaningful, overflowCount: 0);
    }
    return SecondaryNoticeSelection(
      shown: meaningful.sublist(0, effectiveMax),
      overflowCount: meaningful.length - effectiveMax,
    );
  }
}
