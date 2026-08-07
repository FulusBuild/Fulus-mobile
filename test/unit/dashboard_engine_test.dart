import 'package:fulus_mobile/domain/entities/dashboard_summary.dart';
import 'package:fulus_mobile/domain/usecases/dashboard_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = DashboardEngine();

  group('deriveHeroState', () {
    test('an employee always gets EmployeeShiftHero, even on a closed day', () {
      final state = engine.deriveHeroState(
        isOwner: false,
        shiftOrTodayTotal: 4200,
        shiftOrTodaySalesCount: 3,
        dayStatus: ShopDayStatus.closed,
      );
      expect(state, isA<EmployeeShiftHero>());
      expect((state as EmployeeShiftHero).shiftTotal, 4200);
    });

    test('owner + notYetOpened shows yesterday\'s numbers', () {
      final state = engine.deriveHeroState(
        isOwner: true,
        shiftOrTodayTotal: 0,
        shiftOrTodaySalesCount: 0,
        dayStatus: ShopDayStatus.notYetOpened,
        yesterdayTotal: 15000,
        yesterdaySalesCount: 12,
      );
      expect(state, isA<NotYetOpenedHero>());
      expect((state as NotYetOpenedHero).yesterdayTotal, 15000);
      expect(state.yesterdaySalesCount, 12);
    });

    test('owner + open, well before typical closing hour: not emphasized', () {
      final state = engine.deriveHeroState(
        isOwner: true,
        shiftOrTodayTotal: 3000,
        shiftOrTodaySalesCount: 2,
        dayStatus: ShopDayStatus.open,
        now: DateTime(2026, 7, 30, 14, 0), // 2pm
        typicalClosingHour: 20,
      );
      expect(state, isA<OpenHero>());
      expect((state as OpenHero).closeShopEmphasized, isFalse);
    });

    test('owner + open, at/after typical closing hour: emphasized', () {
      final state = engine.deriveHeroState(
        isOwner: true,
        shiftOrTodayTotal: 3000,
        shiftOrTodaySalesCount: 2,
        dayStatus: ShopDayStatus.open,
        now: DateTime(2026, 7, 30, 20, 30), // 8:30pm
        typicalClosingHour: 20,
      );
      expect((state as OpenHero).closeShopEmphasized, isTrue);
    });

    test('owner + closed shows the final total, not "today so far" framing', () {
      final state = engine.deriveHeroState(
        isOwner: true,
        shiftOrTodayTotal: 50000,
        shiftOrTodaySalesCount: 40,
        dayStatus: ShopDayStatus.closed,
      );
      expect(state, isA<ClosedHero>());
      expect((state as ClosedHero).finalTotal, 50000);
    });
  });

  group('selectSecondaryNotices', () {
    test('caps at two even when three or more are meaningful', () {
      final selection = engine.selectSecondaryNotices([
        const SecondaryNotice(type: SecondaryNoticeType.lowStock, label: 'Low stock', value: 5),
        const SecondaryNotice(type: SecondaryNoticeType.pendingCredit, label: 'Credit', value: 12000),
        const SecondaryNotice(type: SecondaryNoticeType.unsyncedItems, label: 'Unsynced', value: 3),
      ]);
      expect(selection.shown.length, 2);
      expect(selection.overflowCount, 1);
    });

    test('orders by priority: low stock, then pending credit, then unsynced', () {
      final selection = engine.selectSecondaryNotices([
        const SecondaryNotice(type: SecondaryNoticeType.unsyncedItems, label: 'Unsynced', value: 3),
        const SecondaryNotice(type: SecondaryNoticeType.lowStock, label: 'Low stock', value: 5),
      ]);
      expect(selection.shown.first.type, SecondaryNoticeType.lowStock);
    });

    test('drops notices whose value is exactly zero', () {
      final selection = engine.selectSecondaryNotices([
        const SecondaryNotice(type: SecondaryNoticeType.lowStock, label: 'Low stock', value: 0),
        const SecondaryNotice(type: SecondaryNoticeType.pendingCredit, label: 'Credit', value: 500),
      ]);
      expect(selection.shown.length, 1);
      expect(selection.shown.first.type, SecondaryNoticeType.pendingCredit);
    });

    test('returns no overflow when two or fewer are meaningful', () {
      final selection = engine.selectSecondaryNotices([
        const SecondaryNotice(type: SecondaryNoticeType.lowStock, label: 'Low stock', value: 5),
      ]);
      expect(selection.overflowCount, 0);
    });
  });
}
