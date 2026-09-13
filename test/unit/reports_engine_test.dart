import 'package:fulus_mobile/domain/entities/report.dart';
import 'package:fulus_mobile/domain/usecases/reports_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = ReportsEngine();

  group('resolvePeriod', () {
    test('today resolves to a single-day range', () {
      final period = engine.resolvePeriod(ReportPeriodKind.today, now: DateTime(2026, 7, 30, 15, 42));
      expect(period.start, DateTime(2026, 7, 30));
      expect(period.end, DateTime(2026, 7, 30));
    });

    test('thisWeek starts on Monday', () {
      final period = engine.resolvePeriod(ReportPeriodKind.thisWeek, now: DateTime(2026, 7, 30));
      expect(period.start, DateTime(2026, 7, 27));
      expect(period.end, DateTime(2026, 7, 30));
    });

    test('thisWeek on a Monday starts on itself', () {
      final period = engine.resolvePeriod(ReportPeriodKind.thisWeek, now: DateTime(2026, 8, 3));
      expect(period.start, DateTime(2026, 8, 3));
    });

    test('thisMonth starts on the 1st', () {
      final period = engine.resolvePeriod(ReportPeriodKind.thisMonth, now: DateTime(2026, 7, 30));
      expect(period.start, DateTime(2026, 7, 1));
      expect(period.end, DateTime(2026, 7, 30));
    });

    test('custom requires both bounds', () {
      expect(() => engine.resolvePeriod(ReportPeriodKind.custom), throwsArgumentError);
    });

    test('custom uses the given bounds, date-truncated', () {
      final period = engine.resolvePeriod(
        ReportPeriodKind.custom,
        customStart: DateTime(2026, 6, 1, 9),
        customEnd: DateTime(2026, 6, 15, 23),
      );
      expect(period.start, DateTime(2026, 6, 1));
      expect(period.end, DateTime(2026, 6, 15));
    });
  });

  group('ReportPeriod.previous', () {
    test('a 7-day period previous is the 7 days immediately before it', () {
      final period = ReportPeriod(kind: ReportPeriodKind.thisWeek, start: DateTime(2026, 7, 27), end: DateTime(2026, 8, 2));
      final prev = period.previous;
      expect(prev.end, DateTime(2026, 7, 26));
      expect(prev.start, DateTime(2026, 7, 20));
    });

    test('a single-day period previous is the single day before it', () {
      final period = ReportPeriod(kind: ReportPeriodKind.today, start: DateTime(2026, 7, 30), end: DateTime(2026, 7, 30));
      final prev = period.previous;
      expect(prev.start, DateTime(2026, 7, 29));
      expect(prev.end, DateTime(2026, 7, 29));
    });
  });

  group('salesInsights', () {
    test('describes recorded facts without forecasting', () {
      final insights = engine.salesInsights(
        byPaymentMethod: const [
          SalesByPaymentMethod(method: 'Cash', total: 900, count: 3),
          SalesByPaymentMethod(method: 'Card', total: 100, count: 1),
        ],
        byHour: const [SalesByHour(hour: 14, total: 1000, count: 4)],
        topProducts: const [TopProduct(productId: 'p1', productName: 'Rice', quantitySold: 4, revenue: 1000)],
      );
      expect(insights.map((i) => i.text).join(' '), contains('Most sales were paid by Cash'));
      expect(insights.map((i) => i.text).join(' '), contains('busiest hour was 2pm-3pm'));
      expect(insights.map((i) => i.text).join(' '), contains('Rice was your top-selling product'));
      expect(insights.every((i) => !i.text.toLowerCase().contains('will')),
          isTrue);
    });
  });

  group('inventoryInsights', () {
    test('reports only observed inventory conditions', () {
      final insights = engine.inventoryInsights(
        lowStockCount: 2,
        outOfStockCount: 1,
        notSoldInThirtyDaysCount: 3,
      );
      expect(insights.map((i) => i.text).join(' '), contains('1 product out of stock'));
      expect(insights.map((i) => i.text).join(' '), contains('2 products running low'));
      expect(insights.map((i) => i.text).join(' '), contains('3 products haven\'t sold'));
    });
  });

  group('customerInsights', () {
    test('surfaces new customers, top customer, and outstanding credit', () {
      final insights = engine.customerInsights(
        newCustomersThisPeriod: 2,
        totalOutstandingCredit: 500,
        topCustomers: const [TopCustomer(customerId: 'c1', customerName: 'Amina', totalSpend: 1200)],
      );
      expect(insights.map((i) => i.text).join(' '), contains('2 new customers'));
      expect(insights.map((i) => i.text).join(' '), contains('Amina was your top customer'));
      expect(insights.map((i) => i.text).join(' '), contains('outstanding customer credit'));
    });
  });

  group('financeInsights', () {
    test('omits the trend line when there is no previous period data', () {
      final insights = engine.financeInsights(netProfit: 1000, previousNetProfit: null);
      expect(insights.any((i) => i.text.contains('versus')), isFalse);
    });

    test('omits the trend line when previous profit was exactly zero', () {
      final insights = engine.financeInsights(netProfit: 1000, previousNetProfit: 0);
      expect(insights.any((i) => i.text.contains('versus')), isFalse);
    });

    test('reports an upward trend correctly', () {
      final insights = engine.financeInsights(netProfit: 1500, previousNetProfit: 1000);
      expect(insights.any((i) => i.text.contains('up 50.0%')), isTrue);
    });

    test('flags a loss-making period', () {
      final insights = engine.financeInsights(netProfit: -200);
      expect(insights.first.text, contains('Expenses exceeded revenue'));
    });
  });

  group('employeeInsights', () {
    test('returns nothing for an empty roster', () {
      expect(engine.employeeInsights(const []), isEmpty);
    });

    test('never names an individual employee', () {
      final insights = engine.employeeInsights([
        const EmployeePerformance(
          employeeId: 'e1',
          employeeName: 'Ada',
          salesTotal: 100,
          salesCount: 2,
          daysPresent: 5,
          daysAbsent: 0,
          daysLate: 0,
        ),
      ]);
      expect(insights.any((i) => i.text.contains('Ada')), isFalse);
    });
  });
}
