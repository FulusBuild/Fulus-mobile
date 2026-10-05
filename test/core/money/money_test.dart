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
  });
}
