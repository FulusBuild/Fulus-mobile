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
      // 2026-07-30 is a Thursday.
      final period = engine.resolvePeriod(ReportPeriodKind.thisWeek, now: DateTime(2026, 7, 30));
      expect(period.start, DateTime(2026, 7, 27)); // Monday
      expect(period.end, DateTime(2026, 7, 30));
    });

    test('thisWeek on a Monday starts on itself', () {
      final period = engine.resolvePeriod(ReportPeriodKind.thisWeek, now: DateTime(2026, 8, 3)); // a Monday
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
    test('a 7-day period\'s previous is the 7 days immediately before it', () {
      final period = ReportPeriod(kind: ReportPeriodKind.thisWeek, start: DateTime(2026, 7, 27), end: DateTime(2026, 8, 2));
      final prev = period.previous;
      expect(prev.end, DateTime(2026, 7, 26));
      expect(prev.start, DateTime(2026, 7, 20));
    });

    test('a single-day period\'s previous is the single day before it', () {
      final period = ReportPeriod(kind: ReportPeriodKind.today, start: DateTime(2026, 7, 30), end: DateTime(2026, 7, 30));
      final prev = period.previous;
      expect(prev.start, DateTime(2026, 7, 29));
      expect(prev.end, DateTime(2026, 7, 29));
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
