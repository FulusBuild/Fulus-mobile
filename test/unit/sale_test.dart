import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/core/money/money.dart';
import 'package:fulus_mobile/domain/entities/sale.dart';

/// No dedicated test file existed for Sale's computed getters before
/// this — they were only ever exercised indirectly through repository
/// tests. Covers balanceDue/paymentStatus (pre-existing, correct) and
/// changeDue (added as part of a confirmed business-logic audit bug
/// fix: no "change due" concept existed anywhere in this app despite
/// full cash overpayment being possible).
void main() {
  Sale saleWith({required Money total, required Money amountPaid, Money? cashTendered}) {
    final now = DateTime(2026, 1, 15);
    return Sale(
      localId: 'sale-1',
      clientReference: 'sale-1',
      locationId: 'loc-1',
      saleDate: now,
      subtotal: total,
      discount: moneyFromMajor(0),
      tax: moneyFromMajor(0),
      total: total,
      amountPaid: amountPaid,
      cashTendered: cashTendered ?? amountPaid,
      cashChange: (cashTendered ?? amountPaid) > amountPaid ? (cashTendered ?? amountPaid) - amountPaid : 0,
      items: const [],
      createdAt: now,
      updatedAt: now,
    );
  }

  group('Sale.balanceDue / changeDue / paymentStatus — combined behavior',
      () {
    test('fully paid: balanceDue and changeDue both zero, status paid', () {
      final sale = saleWith(total: moneyFromMajor(1000), amountPaid: moneyFromMajor(1000));
      expect(sale.balanceDue, moneyFromMajor(0));
      expect(sale.changeDue, moneyFromMajor(0));
      expect(sale.paymentStatus, 'paid');
    });

    test('partially paid: balanceDue is the shortfall, changeDue stays '
        'zero, status partial', () {
      final sale = saleWith(total: moneyFromMajor(1000), amountPaid: moneyFromMajor(600));
      expect(sale.balanceDue, moneyFromMajor(400));
      expect(sale.changeDue, moneyFromMajor(0));
      expect(sale.paymentStatus, 'partial');
    });

    test('unpaid: balanceDue is the full total, changeDue zero, status '
        'unpaid', () {
      final sale = saleWith(total: moneyFromMajor(1000), amountPaid: moneyFromMajor(0));
      expect(sale.balanceDue, moneyFromMajor(1000));
      expect(sale.changeDue, moneyFromMajor(0));
      expect(sale.paymentStatus, 'unpaid');
    });

    test(
        'overpaid (cash tendered exceeds total): changeDue is the excess, '
        'balanceDue stays zero because tendered cash is separate from applied amount — '
        'ReceiptData.balanceDue, which deliberately does floor for '
        'display — status still reads paid', () {
      final sale = saleWith(total: moneyFromMajor(1000), amountPaid: moneyFromMajor(1000), cashTendered: moneyFromMajor(1500));
      expect(sale.changeDue, moneyFromMajor(500));
      expect(sale.balanceDue, moneyFromMajor(0));
      expect(sale.paymentStatus, 'paid');
    });

    test('balanceDue and changeDue are never both greater than zero at '
        'the same time, across the full range from unpaid to overpaid',
        () {
      for (final cashTendered in [0.0, 250.0, 600.0, 999.99, 1000.0, 1000.01, 1500.0]) {
        final applied = cashTendered < 1000 ? cashTendered : 1000.0;
        final sale = saleWith(
          total: moneyFromMajor(1000),
          amountPaid: moneyFromMajor(applied),
          cashTendered: moneyFromMajor(cashTendered),
        );
        final bothOwed = sale.balanceDue > 0 && sale.changeDue > 0;
        expect(
          bothOwed,
          isFalse,
          reason: 'at cashTendered=$cashTendered, balanceDue=${sale.balanceDue} '
              'and changeDue=${sale.changeDue} were both positive',
        );
      }
    });

    test('exactly one kobo underpaid still reads as partial, not paid '
        '(the >= boundary in paymentStatus)', () {
      final sale = saleWith(total: moneyFromMajor(1000), amountPaid: moneyFromMajor(999.99));
      expect(sale.paymentStatus, 'partial');
      expect(sale.changeDue, moneyFromMajor(0));
    });

    test('exactly one kobo overpaid already counts as change due, not '
        'just paid', () {
      final sale = saleWith(total: moneyFromMajor(1000), amountPaid: moneyFromMajor(1000), cashTendered: moneyFromMajor(1000.01));
      expect(sale.paymentStatus, 'paid');
      expect(sale.changeDue, moneyFromMajor(0.01));
    });
  });
}
