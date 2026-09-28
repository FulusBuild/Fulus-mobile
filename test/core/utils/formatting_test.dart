import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/core/utils/formatting.dart';

void main() {
  group('formatMoney', () {
    test('keeps million amounts fully expanded', () {
      expect(formatMoney(1000000), '₦1,000,000.00');
      expect(formatMoney(1500000), '₦1,500,000.00');
    });

    test('formats thousands and decimals consistently', () {
      expect(formatMoney(1234.5), '₦1,234.50');
      expect(formatMoney(0), '₦0.00');
      expect(formatMoney(-2500), '-₦2,500.00');
    });

    test('supports custom symbols and explicit signs', () {
      expect(formatMoney(1000000, symbol: '$'), '$1,000,000.00');
      expect(formatMoney(1250, showSign: true), '+₦1,250.00');
    });
  });
}
