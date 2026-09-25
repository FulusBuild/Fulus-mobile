import '../entities/dashboard_summary.dart';

/// Stage 12 (Home half). One method: whoever is logged in gets whatever
/// hero state applies to them right now. The branching between owner
/// and employee views, and between the day-status variants, happens
/// inside DashboardEngine (pure) — this repository's implementation
/// only fetches the raw numbers (today's/yesterday's totals and counts,
/// low-stock/credit/unsynced counts) and hands them to the engine.
abstract class DashboardRepository {
  /// [currentAuthUserId] and [isOwner] come from Stage 2's session — see
  /// dashboard_engine.dart's doc comment on why this module takes them
  /// as plain parameters rather than reading the session itself.
  Future<HomeHeroState> getHeroState({
    required String currentAuthUserId,
    required bool isOwner,
    required String locationId,
  });

  /// Redesign pass — [max] is new (default `2`, matching the existing,
  /// still-tested Decision 12 cap exactly, so every current caller and
  /// test keeps its old behavior unchanged). Home's new dashboard-style
  /// notice row asks for a higher [max] so it can show all three
  /// categories at once, per the explicit product decision to make
  /// Home richer than Decision 12's single-hero restraint for this
  /// redesign; nothing else in the app needs a different value than
  /// the default.
  Future<SecondaryNoticeSelection> getSecondaryNotices({
    required String locationId,
    int max = 2,
  });
}
