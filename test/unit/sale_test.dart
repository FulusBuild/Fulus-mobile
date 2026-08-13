import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/domain/entities/sale.dart';

/// No dedicated test file existed for Sale's computed getters before
/// this — they were only ever exercised indirectly through repository
/// tests. Covers balanceDue/paymentStatus (pre-existing, correct) and
/// changeDue (added as part of a confirmed business-logic audit bug
/// fix: no "change due" concept existed anywhere in this app despite
/// full cash overpayment being possible).
void main() {
  Sale saleWith({required double total, required double amountPaid}) {
    final now = DateTime(2026, 1, 15);
    return Sale(
      localId: 'sale-1',
      clientReference: 'sale-1',
      locationId: 'loc-1',
      saleDate: now,
      subtotal: total,
      discount: 0,
      tax: 0,
      total: total,
      amountPaid: amountPaid,
      items: const [],
      createdAt: now,
      updatedAt: now,
    );
  }

  group('Sale.balanceDue / changeDue / paymentStatus — combined behavior',
      () {
    test('fully paid: balanceDue and changeDue both zero, status paid', () {
      final sale = saleWith(total: 1000, amountPaid: 1000);
      expect(sale.balanceDue, 0);
      expect(sale.changeDue, 0);
      expect(sale.paymentStatus, 'paid');
    });

    test('partially paid: balanceDue is the shortfall, changeDue stays '
        'zero, status partial', () {
      final sale = saleWith(total: 1000, amountPaid: 600);
      expect(sale.balanceDue, 400);
      expect(sale.changeDue, 0);
      expect(sale.paymentStatus, 'partial');
    });

    test('unpaid: balanceDue is the full total, changeDue zero, status '
        'unpaid', () {
      final sale = saleWith(total: 1000, amountPaid: 0);
      expect(sale.balanceDue, 1000);
      expect(sale.changeDue, 0);
      expect(sale.paymentStatus, 'unpaid');
    });

    test(
        'overpaid (cash tendered exceeds total): changeDue is the excess, '
        'balanceDue goes negative — not floored here, unlike '
        'ReceiptData.balanceDue, which deliberately does floor for '
        'display — status still reads paid', () {
      final sale = saleWith(total: 1000, amountPaid: 1500);
      expect(sale.changeDue, 500);
      expect(sale.balanceDue, -500);
      expect(sale.paymentStatus, 'paid');
    });

    test('balanceDue and changeDue are never both greater than zero at '
        'the same time, across the full range from unpaid to overpaid',
        () {
      for (final amountPaid in [0.0, 250.0, 600.0, 999.99, 1000.0, 1000.01, 1500.0]) {
        final sale = saleWith(total: 1000, amountPaid: amountPaid);
        final bothOwed = sale.balanceDue > 0 && sale.changeDue > 0;
        expect(
          bothOwed,
          isFalse,
          reason: 'at amountPaid=$amountPaid, balanceDue=${sale.balanceDue} '
              'and changeDue=${sale.changeDue} were both positive',
        );
      }
    });

    test('exactly one kobo underpaid still reads as partial, not paid '
        '(the >= boundary in paymentStatus)', () {
      final sale = saleWith(total: 1000, amountPaid: 999.99);
      expect(sale.paymentStatus, 'partial');
      expect(sale.changeDue, 0);
    });

    test('exactly one kobo overpaid already counts as change due, not '
        'just paid', () {
      final sale = saleWith(total: 1000, amountPaid: 1000.01);
      expect(sale.paymentStatus, 'paid');
      expect(sale.changeDue, closeTo(0.01, 0.0001));
    });
  });
}
