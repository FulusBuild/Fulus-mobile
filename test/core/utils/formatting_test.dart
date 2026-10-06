import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/core/money/money.dart';
import 'package:fulus_mobile/core/utils/formatting.dart';

void main() {
  group('formatMoney', () {
    test('keeps million amounts fully expanded', () {
      expect(formatMoney(moneyFromMajor(1000000)), '₦1,000,000.00');
      expect(formatMoney(moneyFromMajor(1500000)), '₦1,500,000.00');
    });

    test('formats thousands and decimals consistently', () {
      expect(formatMoney(moneyFromMajor(1234.5)), '₦1,234.50');
      expect(formatMoney(moneyFromMajor(0)), '₦0.00');
      expect(formatMoney(moneyFromMajor(-2500)), '-₦2,500.00');
    });

    test('formats signs and large integer minor units without floating-point drift', () {
      expect(formatMoney(9007199254740991), '₦90,071,992,547,409.91');
      expect(formatMoney(1250, showSign: true), '+₦12.50');
      expect(formatMoney(-1250, showSign: true), '-₦12.50');
    });

  });
}
