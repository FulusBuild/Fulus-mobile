import 'package:flutter_test/flutter_test.dart';

import 'package:fulus_mobile/core/business_engine/draft_cart_aggregation.dart';

void main() {
  group('combineDiscount', () {
    test('sums the whole-cart discount and every line discount', () {
      expect(
        combineDiscount(
          wholeCartDiscount: 200,
          lineDiscounts: [50, 30],
        ),
        280,
      );
    });

    test('zero whole-cart discount with no line discounts is zero', () {
      expect(
        combineDiscount(wholeCartDiscount: 0, lineDiscounts: const []),
        0,
      );
    });

    test('works with only line discounts, no whole-cart discount', () {
      expect(
        combineDiscount(wholeCartDiscount: 0, lineDiscounts: [100, 50]),
        150,
      );
    });
  });

  group('computeRemainingToPay', () {
    test('total minus the sum of payments so far', () {
      expect(
        computeRemainingToPay(total: 10000, paymentAmounts: [3000, 2000]),
        5000,
      );
    });

    test('zero when payments already cover the total exactly', () {
      expect(computeRemainingToPay(total: 5000, paymentAmounts: [5000]), 0);
    });

    test('negative when payments exceed the total', () {
      expect(computeRemainingToPay(total: 5000, paymentAmounts: [6000]), -1000);
    });

    test('the full total when no payments have been made yet', () {
      expect(computeRemainingToPay(total: 5000, paymentAmounts: const []), 5000);
    });
  });

  group('aggregatePaymentMethod', () {
    test('null when there are no payments', () {
      expect(aggregatePaymentMethod(const []), isNull);
    });

    test('the single method when there is only one payment', () {
      expect(aggregatePaymentMethod(['cash']), 'cash');
    });

    test('the shared method when every leg used the same one', () {
      expect(aggregatePaymentMethod(['cash', 'cash']), 'cash');
    });

    test('"split" when methods genuinely differ', () {
      expect(aggregatePaymentMethod(['cash', 'transfer']), 'split');
    });
  });

  group('computeCashAmountPaid', () {
    test('sums every leg when none of them are credit', () {
      expect(
        computeCashAmountPaid(const [(method: 'cash', amount: 2000), (method: 'transfer', amount: 3000)]),
        5000,
      );
    });

    test('zero when the only leg is credit', () {
      expect(computeCashAmountPaid(const [(method: 'credit', amount: 5000)]), 0);
    });

    // Regression case: this is the exact split from the "Paid in full"
    // bug — before the fix, this summed to 2500000 (the full total),
    // not the 1000000 that was actually collected.
    test('excludes a credit leg from a cash+credit split', () {
      expect(
        computeCashAmountPaid(const [(method: 'cash', amount: 1000000), (method: 'credit', amount: 1500000)]),
        1000000,
      );
    });

    test('empty payments is zero', () {
      expect(computeCashAmountPaid(const []), 0);
    });
  });
}
