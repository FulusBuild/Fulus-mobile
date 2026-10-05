import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/core/money/money.dart';

void main() {
  test('every financial wire field uses the same decimal-string boundary', () {
    const wireFields = <String>[
      'amount',
      'credit_limit',
      'outstanding_balance',
      'opening_cash',
      'closing_cash',
      'cash_difference',
      'subtotal',
      'whole_cart_discount',
      'discount',
      'tax',
      'total',
      'amount_paid',
      'cash_tendered',
      'cash_change',
      'unit_price',
      'cost_price_at_sale',
      'line_total',
      'cost_price',
      'selling_price',
      'refund_amount',
      'salary',
    ];

    for (final field in wireFields) {
      final decoded = moneyFromWire('300.00');
      expect(decoded, 30000, reason: 'wire field $field must decode 300.00 as 30,000 minor units');

      final converter = const MoneyJsonConverter();
      expect(converter.toJson(decoded), '300.00');
      expect(converter.fromJson('300.00'), decoded);
      expect(
        () => converter.fromJson(300),
        throwsFormatException,
        reason: 'wire field $field must not accept ambiguous JSON number 300',
      );
    }
  });

  test('the reported product case cannot become 30,000 major units', () {
    const productPrice = 30000; // ₦300.00 in integer minor units.
    final wire = moneyToWire(productPrice);

    expect(wire, '300.00');
    expect(moneyFromWire(wire), productPrice);
    expect(() => moneyFromWire(300), throwsFormatException);
  });

  test('sub-major values and large values remain exact at the wire boundary', () {
    for (final value in <Money>[1, 9, 10, 99, 100, 1001, 999999999999, -1, -1001]) {
      expect(moneyFromWire(moneyToWire(value)), value);
    }
  });
}
