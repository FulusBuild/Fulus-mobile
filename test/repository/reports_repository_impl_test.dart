import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:fulus_mobile/data/repositories/reports_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/report.dart';

/// No test file existed for ReportsRepositoryImpl before this one — that
/// gap is exactly why the bug below shipped unnoticed while its correct
/// sibling (FinanceStatsRepositoryImpl, covered by
/// finance_stats_repository_test.dart) was already tested.
void main() {
  late AppDatabase db;
  late ReportsRepositoryImpl repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = ReportsRepositoryImpl(db: db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertLocation(String id) async {
    await db.into(db.locations).insert(
          LocationsCompanion.insert(
            localId: id,
            name: 'Test Location',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            syncStatus: SyncStatus.settled,
          ),
        );
  }

  Future<void> insertCompletedSale({
    required String localId,
    required String locationId,
    required DateTime saleDate,
    required double total,
    required double amountPaid,
    required List<({double costPriceAtSale, int quantity})> items,
  }) async {
    await db.into(db.sales).insert(
          SalesCompanion.insert(
            localId: localId,
            clientReference: localId,
            locationId: locationId,
            saleDate: saleDate,
            subtotal: total,
            total: total,
            amountPaid: Value(amountPaid),
            createdAt: saleDate,
            updatedAt: saleDate,
            syncStatus: SyncStatus.settled,
          ),
        );
    for (var i = 0; i < items.length; i++) {
      await db.into(db.saleItems).insert(
            SaleItemsCompanion.insert(
              localId: '$localId-item-$i',
              saleLocalId: localId,
              quantity: items[i].quantity,
              unitPrice: 100,
              costPriceAtSale: items[i].costPriceAtSale,
            ),
          );
    }
  }

  Future<void> insertExpense({
    required String localId,
    required String locationId,
    required double amount,
    required DateTime date,
  }) async {
    await db.into(db.expenses).insert(
          ExpensesCompanion.insert(
            localId: localId,
            locationId: locationId,
            description: 'Test expense',
            amount: amount,
            expenseDate: date,
            createdAt: date,
            updatedAt: date,
            syncStatus: SyncStatus.settled,
          ),
        );
  }

  group('getFinanceReport — net profit (business-logic audit bug fix)', () {
    test(
        'nets cost of goods sold, not just expenses — the confirmed bug: '
        'this used to be revenue - expenses only', () async {
      await insertLocation('loc-1');
      // Same scenario as finance_stats_repository_test.dart's
      // 'net profit nets cost of goods sold and expenses from revenue'
      // test, so the two repositories can be checked against each
      // other directly: revenue 1000, COGS 300 (5 units @ cost 60),
      // expenses 200.
      await insertCompletedSale(
        localId: 'sale-1',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 1, 15),
        total: 1000,
        amountPaid: 1000,
        items: [(costPriceAtSale: 60, quantity: 5)],
      );
      await insertExpense(
        localId: 'expense-1',
        locationId: 'loc-1',
        amount: 200,
        date: DateTime(2026, 1, 10),
      );

      final report = await repository.getFinanceReport(
        ReportPeriod(
          kind: ReportPeriodKind.custom,
          start: DateTime(2026, 1, 1),
          end: DateTime(2026, 1, 31),
        ),
      );

      expect(report.totalRevenue, 1000);
      expect(report.totalCostOfGoodsSold, 300);
      expect(report.totalExpenses, 200);
      expect(report.grossProfit, 700);
      // Before the fix this returned 800 (1000 - 200, COGS never
      // subtracted) — the exact defect this pins down. Matches
      // FinanceStatsRepositoryImpl.getProfitLoss's netProfit for the
      // identical seeded data.
      expect(report.netProfit, 500);
    });

    test('a Quick Sale line (no catalog product, cost 0) correctly '
        'contributes nothing to cost of goods sold', () async {
      await insertLocation('loc-1');
      await insertCompletedSale(
        localId: 'sale-1',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 1, 15),
        total: 500,
        amountPaid: 500,
        items: [(costPriceAtSale: 0, quantity: 3)],
      );

      final report = await repository.getFinanceReport(
        ReportPeriod(
          kind: ReportPeriodKind.custom,
          start: DateTime(2026, 1, 1),
          end: DateTime(2026, 1, 31),
        ),
      );

      expect(report.totalCostOfGoodsSold, 0);
      expect(report.netProfit, 500);
    });

    test('multiple line items on one sale all contribute to cost of '
        'goods sold', () async {
      await insertLocation('loc-1');
      await insertCompletedSale(
        localId: 'sale-1',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 1, 15),
        total: 1000,
        amountPaid: 1000,
        items: [
          (costPriceAtSale: 60, quantity: 5), // 300
          (costPriceAtSale: 40, quantity: 2), // 80
        ],
      );

      final report = await repository.getFinanceReport(
        ReportPeriod(
          kind: ReportPeriodKind.custom,
          start: DateTime(2026, 1, 1),
          end: DateTime(2026, 1, 31),
        ),
      );

      expect(report.totalCostOfGoodsSold, 380);
    });

    test('the previous-period comparison is COGS-aware too, so the '
        'trend percentage does not compare a corrected figure against '
        'an uncorrected one', () async {
      await insertLocation('loc-1');
      // Current period: revenue 1000, COGS 300, expenses 0 -> profit 700.
      await insertCompletedSale(
        localId: 'sale-current',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 2, 15),
        total: 1000,
        amountPaid: 1000,
        items: [(costPriceAtSale: 60, quantity: 5)],
      );
      // Previous period (same length: Jan 1-31): revenue 1000, COGS
      // 500 (5 units @ cost 100), expenses 0 -> profit 500.
      await insertCompletedSale(
        localId: 'sale-previous',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 1, 15),
        total: 1000,
        amountPaid: 1000,
        items: [(costPriceAtSale: 100, quantity: 5)],
      );

      final report = await repository.getFinanceReport(
        ReportPeriod(
          kind: ReportPeriodKind.custom,
          start: DateTime(2026, 2, 1),
          end: DateTime(2026, 2, 28),
        ),
      );

      expect(report.netProfit, 700);
      // Before the fix, the current period's 800 (COGS omitted) would
      // have been compared against a previous period that (by the same
      // bug) was also COGS-omitted, i.e. 1000 — masking the bug from a
      // trend-only test. Comparing the two CORRECT figures: 700 vs 500
      // previous is a +40% change, not whatever the uncorrected pair
      // would have produced.
      expect(report.previousPeriodNetProfit, 500);
      expect(report.profitTrendPercent, closeTo(40.0, 0.001));
    });

    test('zero sales and zero expenses in range produces a zero net '
        'profit, not a null or error', () async {
      await insertLocation('loc-1');

      final report = await repository.getFinanceReport(
        ReportPeriod(
          kind: ReportPeriodKind.custom,
          start: DateTime(2026, 1, 1),
          end: DateTime(2026, 1, 31),
        ),
      );

      expect(report.totalRevenue, 0);
      expect(report.totalCostOfGoodsSold, 0);
      expect(report.totalExpenses, 0);
      expect(report.netProfit, 0);
      expect(report.previousPeriodNetProfit, isNull);
    });
  });
}
