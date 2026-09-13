import '../entities/dashboard_summary.dart';
import 'dashboard_engine.dart';

/// Converts Home's raw operational signals into a small set of actions.
///
/// Home should answer "what should I do next?" rather than merely report
/// numbers. This remains pure so the ordering is deterministic offline and
/// can be reused by presentation, notifications, or future automation.
class HomeAttentionEngine {
  const HomeAttentionEngine();

  List<HomeAttention> prioritize({
    required bool canViewDashboardStats,
    required ShopDayStatus dayStatus,
    required List<SecondaryNotice> notices,
    required bool hasTodayActivity,
  }) {
    // Business-wide attention is permission-scoped, not role-name-scoped.
    // Owners normally have this permission, but Managers may be granted it
    // too. Cashiers/employees without it must never receive business-wide
    // operational actions on Home.
    if (!canViewDashboardStats) return const [];

    final result = <HomeAttention>[];
    final meaningful = notices.where((notice) => notice.value != 0).toList();

    final lowStock = _first(meaningful, SecondaryNoticeType.lowStock);
    if (lowStock != null) {
      result.add(HomeAttention(
        kind: HomeAttentionKind.lowStock,
        label: lowStock.value == 1 ? 'Restock 1 item' : 'Restock ${lowStock.value} items',
        priority: 0,
      ));
    }

    final credit = _first(meaningful, SecondaryNoticeType.pendingCredit);
    if (credit != null) {
      result.add(const HomeAttention(
        kind: HomeAttentionKind.credit,
        label: 'Review credit',
        priority: 1,
      ));
    }

    // The next operational action always beats a technical sync reminder.
    // Sync is useful context, but it should not displace "Open shop" or
    // "Start selling" from the three-item attention budget.
    switch (dayStatus) {
      case ShopDayStatus.notYetOpened:
        result.add(const HomeAttention(
          kind: HomeAttentionKind.openShop,
          label: 'Open shop',
          priority: 2,
        ));
      case ShopDayStatus.open:
        if (!hasTodayActivity) {
          result.add(const HomeAttention(
            kind: HomeAttentionKind.startSelling,
            label: 'Start selling',
            priority: 2,
          ));
        }
      case ShopDayStatus.closed:
        // No reopening action is suggested from Home. A closed business day
        // is history, not an error state.
        break;
    }

    final unsynced = _first(meaningful, SecondaryNoticeType.unsyncedItems);
    if (unsynced != null) {
      result.add(HomeAttention(
        kind: HomeAttentionKind.unsyncedItems,
        label: unsynced.value == 1 ? 'Sync 1 item' : 'Sync ${unsynced.value} items',
        priority: 3,
      ));
    }

    result.sort((a, b) => a.priority.compareTo(b.priority));
    return result.take(3).toList(growable: false);
  }

  SecondaryNotice? _first(
    List<SecondaryNotice> notices,
    SecondaryNoticeType type,
  ) {
    for (final notice in notices) {
      if (notice.type == type) return notice;
    }
    return null;
  }
}

enum HomeAttentionKind { lowStock, credit, openShop, startSelling, unsyncedItems }

class HomeAttention {
  const HomeAttention({
    required this.kind,
    required this.label,
    required this.priority,
  });

  final HomeAttentionKind kind;
  final String label;
  final int priority;
}
