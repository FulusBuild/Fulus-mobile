/// Dashboard / Home — the other half of Stage 12.
///
/// Volume 4 is explicit that Home is NOT a dashboard: "one evolving hero
/// element... not five widgets shown at once." [HomeHeroState] models
/// that literally — a sealed type with one variant per moment Volume 4
/// describes, so the UI layer can never accidentally render more than
/// one hero at a time (there's no shape in which two variants could be
/// held or shown simultaneously).
///
/// Volume 4's five prose-described moments (not-yet-open, just-opened-
/// zero, mid-day, approaching-close, after-close) collapse to three data
/// states here plus the separate employee view (Decision 13) — "just
/// opened, zero sales" and "mid-day, N sales" are the same data shape
/// (today's running total and count) with different values, not
/// different states; "approaching a typical closing hour" is the same
/// state again with [closeShopEmphasized] set, per Volume 4's own words
/// ("unchanged in content, but Close Shop becomes visually more
/// present"). Collapsing these keeps the one-hero-element rule true at
/// the type level, not just by UI convention.
sealed class HomeHeroState {
  const HomeHeroState();
}

/// Before the day's first sale — Volume 4's "Ready to open?" moment.
/// Whether this state applies at all depends on a day-open/day-closed
/// concept that Volume 8's Daily Closing flow (Stage 8, not built yet)
/// owns; see dashboard_engine.dart's [ShopDayStatus] doc comment for how
/// this module stays correct in the meantime.
final class NotYetOpenedHero extends HomeHeroState {
  const NotYetOpenedHero({required this.yesterdayTotal, required this.yesterdaySalesCount});
  final double yesterdayTotal;
  final int yesterdaySalesCount;
}

/// Covers both "open, ₦0 so far" and "open, mid-day, N sales" — see
/// class doc above for why these share one variant.
final class OpenHero extends HomeHeroState {
  const OpenHero({
    required this.todayTotal,
    required this.todaySalesCount,
    this.closeShopEmphasized = false,
    this.yesterdayTotal = 0,
    this.yesterdaySalesCount = 0,
  });
  final double todayTotal;
  final int todaySalesCount;
  final bool closeShopEmphasized;

  /// Redesign pass addition — DashboardRepositoryImpl already fetched
  /// yesterday's total for the [NotYetOpenedHero] case; it was
  /// discarded rather than reused for the (far more common) open-day
  /// case. Defaults to 0 so every existing construction of [OpenHero]
  /// (dashboard_engine_test.dart included) keeps compiling and passing
  /// unchanged. Zero is also the correct "no comparison available"
  /// value here, not just a safe default — see [HomeHeroState] callers'
  /// own "never shown as '0% vs yesterday'" rule for why a UI reading
  /// this must treat 0 as "omit the comparison," never as a real -100%.
  final double yesterdayTotal;
  final int yesterdaySalesCount;
}

/// After Close Shop / Daily Closing — "a number that's now history."
final class ClosedHero extends HomeHeroState {
  const ClosedHero({required this.finalTotal, required this.finalSalesCount});
  final double finalTotal;
  final int finalSalesCount;
}

/// Kwame's Home (Decision 13) — an employee login's OWN shift, never the
/// business total, never Open/Close Shop. This is not "OpenHero with
/// some fields hidden"; per Decision 13 that framing was explicitly
/// rejected, which is why this is its own sealed variant rather than a
/// flag on OpenHero.
final class EmployeeShiftHero extends HomeHeroState {
  const EmployeeShiftHero({required this.shiftTotal, required this.shiftSalesCount});
  final double shiftTotal;
  final int shiftSalesCount;
}

enum SecondaryNoticeType { lowStock, pendingCredit, unsyncedItems }

/// A single tappable Home notice — Decision 12's hard cap of two applies
/// to how many of these ever reach the UI at once; see
/// DashboardEngine.selectSecondaryNotices.
class SecondaryNotice {
  const SecondaryNotice({required this.type, required this.label, required this.value});
  final SecondaryNoticeType type;
  final String label;
  final num value;
}

/// The final, capped-at-two set Home actually renders, plus how many
/// more genuine notices exist beyond that — Decision 12: "the single
/// most urgent one plus a plain 'and 2 more'."
class SecondaryNoticeSelection {
  const SecondaryNoticeSelection({required this.shown, required this.overflowCount});
  final List<SecondaryNotice> shown;
  final int overflowCount;
}
