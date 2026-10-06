import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/core/money/money.dart';

void main() {
  group('integer money contract', () {
    test('converts major units to exact minor units', () {
      expect(moneyFromMajor(0), 0);
      expect(moneyFromMajor(10), 1000);
      expect(moneyFromMajor(10.01), 1001);
      expect(moneyFromMajor(0.1), 10);
    });

    test('formats minor units as canonical two-decimal wire values', () {
      expect(moneyToWire(0), '0.00');
      expect(moneyToWire(1001), '10.01');
      expect(moneyToWire(-1001), '-10.01');
    });

    test('parses the strict decimal-string cloud wire contract', () {
      expect(moneyFromWire('10.01'), 1001);
      expect(moneyFromWire('10.00'), 1000);
      expect(moneyFromWire('0.10'), 10);
      expect(moneyFromWire('-10.01'), -1001);
    });

    test('rejects ambiguous JSON numeric money values', () {
      expect(() => moneyFromWire(300), throwsFormatException);
      expect(() => moneyFromWire(300.00), throwsFormatException);
      expect(() => moneyFromWire(300.01), throwsFormatException);
      expect(() => moneyFromWire('300'), throwsFormatException);
      expect(() => moneyFromWire('300.0'), throwsFormatException);
      expect(() => moneyFromWire('+300.00'), throwsFormatException);
    });

    test('round trips two-decimal values exactly', () {
      for (final value in <Money>[0, 1, 10, 99, 100, 999, 1000, 1001, 1000000, -1001]) {
        expect(moneyFromWire(moneyToWire(value)), value);
      }
    });

    test('rejects more than two fractional digits', () {
      expect(() => moneyFromWire('10.001'), throwsFormatException);
    });


    test('preserves benchmark price-times-quantity magnitude exactly', () {
      const unitPrice = 30000; // ₦300.00
      const quantity = 100;
      final total = unitPrice * quantity;
      expect(total, 3000000); // ₦30,000.00
      expect(moneyToWire(total), '30000.00');
      expect(moneyFromWire('30000.00'), total);
    });

    test('preserves amounts below one major unit', () {
      for (final value in <Money>[1, 9, 10, 99]) {
        expect(moneyFromWire(moneyToWire(value)), value);
      }
    });

    test('preserves large and negative financial adjustments exactly', () {
      const values = <Money>[
        9007199254740991,
        92233720368547700,
        -1,
        -99,
        -1001,
        -9007199254740991,
      ];

      for (final value in values) {
        expect(moneyFromWire(moneyToWire(value)), value);
      }
    });

    test('preserves split-payment and credit identities in minor units', () {
      const total = 100000; // ₦1,000.00
      const cash = 30000;
      const card = 20000;
      const credit = 50000;

      expect(cash + card + credit, total);
      expect(cash + card, 50000); // amount collected
      expect(total - (cash + card), credit); // balance due
    });

    test('preserves cash tender and change identity in minor units', () {
      const tendered = 100000; // ₦1,000.00
      const applied = 75000; // ₦750.00
      final change = tendered - applied;

      expect(change, 25000);
      expect(moneyToWire(tendered), '1000.00');
      expect(moneyToWire(applied), '750.00');
      expect(moneyToWire(change), '250.00');
    });

  });
}
