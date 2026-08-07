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
  });

  Future<SecondaryNoticeSelection> getSecondaryNotices();
}
