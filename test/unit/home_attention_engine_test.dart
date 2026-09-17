import 'package:fulus_mobile/domain/entities/dashboard_summary.dart';
import 'package:fulus_mobile/domain/usecases/dashboard_engine.dart';
import 'package:fulus_mobile/domain/usecases/home_attention_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = HomeAttentionEngine();

  test('employee Home never receives business attention actions', () {
    final result = engine.prioritize(
      canViewDashboardStats: false,
      dayStatus: ShopDayStatus.open,
      notices: const [
        SecondaryNotice(type: SecondaryNoticeType.lowStock, label: 'Low stock', value: 5),
      ],
      hasTodayActivity: false,
    );
    expect(result, isEmpty);
  });

  test('manager with dashboard permission receives business attention actions', () {
    final result = engine.prioritize(
      canViewDashboardStats: true,
      dayStatus: ShopDayStatus.open,
      notices: const [
        SecondaryNotice(type: SecondaryNoticeType.lowStock, label: 'Low stock', value: 2),
      ],
      hasTodayActivity: false,
    );
    expect(result.map((item) => item.kind), [
      HomeAttentionKind.lowStock,
      HomeAttentionKind.startSelling,
    ]);
  });

  test('low stock is prioritized before credit and start selling', () {
    final result = engine.prioritize(
      canViewDashboardStats: true,
      dayStatus: ShopDayStatus.open,
      notices: const [
        SecondaryNotice(type: SecondaryNoticeType.pendingCredit, label: 'Credit', value: 12000),
        SecondaryNotice(type: SecondaryNoticeType.lowStock, label: 'Low stock', value: 2),
      ],
      hasTodayActivity: false,
    );

    expect(result.map((item) => item.kind), [
      HomeAttentionKind.lowStock,
      HomeAttentionKind.credit,
      HomeAttentionKind.startSelling,
    ]);
  });

  test('not yet opened produces Open Shop instead of a fake sales action', () {
    final result = engine.prioritize(
      canViewDashboardStats: true,
      dayStatus: ShopDayStatus.notYetOpened,
      notices: const [],
      hasTodayActivity: false,
    );
    expect(result.single.kind, HomeAttentionKind.openShop);
  });

  test('closed day does not suggest reopening or starting a sale', () {
    final result = engine.prioritize(
      canViewDashboardStats: true,
      dayStatus: ShopDayStatus.closed,
      notices: const [],
      hasTodayActivity: false,
    );
    expect(result, isEmpty);
  });

  test('sync status is never surfaced as a Home attention action', () {
    final result = engine.prioritize(
      canViewDashboardStats: true,
      dayStatus: ShopDayStatus.open,
      notices: const [
        SecondaryNotice(type: SecondaryNoticeType.unsyncedItems, label: 'Unsynced', value: 7),
      ],
      hasTodayActivity: false,
    );

    expect(result.map((item) => item.kind), [HomeAttentionKind.startSelling]);
    expect(result.map((item) => item.label), ['Start selling']);
  });

  test('sync status does not replace a business attention action', () {
    final result = engine.prioritize(
      canViewDashboardStats: true,
      dayStatus: ShopDayStatus.closed,
      notices: const [
        SecondaryNotice(type: SecondaryNoticeType.unsyncedItems, label: 'Unsynced', value: 1),
        SecondaryNotice(type: SecondaryNoticeType.pendingCredit, label: 'Credit', value: 1),
      ],
      hasTodayActivity: true,
    );

    expect(result.map((item) => item.label), ['Review credit']);
  });

  test('attention list stays deliberately small', () {
    final result = engine.prioritize(
      canViewDashboardStats: true,
      dayStatus: ShopDayStatus.open,
      notices: const [
        SecondaryNotice(type: SecondaryNoticeType.lowStock, label: 'Low stock', value: 4),
        SecondaryNotice(type: SecondaryNoticeType.pendingCredit, label: 'Credit', value: 3000),
        SecondaryNotice(type: SecondaryNoticeType.unsyncedItems, label: 'Unsynced', value: 7),
      ],
      hasTodayActivity: false,
    );
    expect(result.length, lessThanOrEqualTo(3));
    expect(result.map((item) => item.kind), [
      HomeAttentionKind.lowStock,
      HomeAttentionKind.credit,
      HomeAttentionKind.startSelling,
    ]);
  });
}
