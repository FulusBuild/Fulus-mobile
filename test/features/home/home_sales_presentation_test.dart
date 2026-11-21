import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/domain/entities/dashboard_summary.dart';
import 'package:fulus_mobile/features/home/presentation/screens/home_screen.dart';

void main() {
  group('Home sales labels', () {
    test('labels the pre-open total as yesterday', () {
      const hero = NotYetOpenedHero(
        yesterdayTotal: 12500,
        yesterdaySalesCount: 1,
      );

      expect(homeSalesPeriodLabel(hero), 'YESTERDAY’S SALES');
      expect(homeSalesCountLabel(hero), '1 sale yesterday');
    });

    test('uses today for an open or closed business day', () {
      const open = OpenHero(todayTotal: 4500, todaySalesCount: 2);
      const closed = ClosedHero(finalTotal: 4500, finalSalesCount: 2);

      expect(homeSalesPeriodLabel(open), 'TODAY’S SALES');
      expect(homeSalesCountLabel(open), '2 sales today');
      expect(homeSalesPeriodLabel(closed), 'TODAY’S SALES');
      expect(homeSalesCountLabel(closed), '2 sales today');
    });

    test('labels an employee total as their shift', () {
      const hero = EmployeeShiftHero(shiftTotal: 3000, shiftSalesCount: 1);

      expect(homeSalesPeriodLabel(hero), 'YOUR SHIFT SALES');
      expect(homeSalesCountLabel(hero), '1 sale this shift');
    });
  });
}
