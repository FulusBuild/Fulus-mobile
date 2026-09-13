import 'package:flutter_test/flutter_test.dart';

import '../../lib/features/money/domain/cash_drawer_state.dart';

void main() {
  group('MoneyExpectedCashPreview', () {
    test('calculates expected cash from opening float, sales and cash expenses', () {
      const preview = MoneyExpectedCashPreview(
        openingFloat: 10000,
        cashSales: 47500,
        cashExpenses: 3500,
      );

      expect(preview.expectedCash, 54000);
    });

    test('keeps non-cash activity out of the drawer calculation', () {
      const preview = MoneyExpectedCashPreview(
        openingFloat: 25000,
        cashSales: 120000,
        cashExpenses: 5000,
      );

      expect(preview.expectedCash, 140000);
    });
  });

  group('DailyClosingSummary', () {
    test('derives total sales and drawer difference', () {
      const summary = DailyClosingSummary(
        closedAt: DateTime(2026, 9, 13, 20),
        salesByMethod: {
          'Cash': 50000,
          'Mobile Money': 30000,
          'Card': 20000,
        },
        expensesTotal: 5000,
        netForDay: 95000,
        expectedCash: 45000,
        countedCash: 43000,
        note: null,
      );

      expect(summary.totalSales, 100000);
      expect(summary.difference, -2000);
    });

    test('a matching count has zero difference', () {
      const summary = DailyClosingSummary(
        closedAt: DateTime(2026, 9, 13, 20),
        salesByMethod: {'Cash': 50000},
        expensesTotal: 0,
        netForDay: 50000,
        expectedCash: 50000,
        countedCash: 50000,
        note: 'All good',
      );

      expect(summary.difference, 0);
    });
  });
}
