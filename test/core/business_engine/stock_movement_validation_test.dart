import 'package:test/test.dart';

import 'package:fulus_mobile/core/business_engine/stock_movement_validation.dart'
    as validation;

// Verified against pubspec.yaml directly: `name: fulus_mobile`.

void main() {
  group('validateMovementQuantity', () {
    test('accepts a positive quantity', () {
      expect(() => validation.validateMovementQuantity(1), returnsNormally);
    });

    test('rejects zero — backend requires gt=0, not ge=0', () {
      expect(
        () => validation.validateMovementQuantity(0),
        throwsArgumentError,
      );
    });

    test('rejects a negative quantity', () {
      expect(
        () => validation.validateMovementQuantity(-5),
        throwsArgumentError,
      );
    });
  });

  group('validateAdjustmentTarget', () {
    test('accepts zero — "All sold" is a real, expected target', () {
      expect(() => validation.validateAdjustmentTarget(0), returnsNormally);
    });

    test('accepts a positive target', () {
      expect(() => validation.validateAdjustmentTarget(50), returnsNormally);
    });

    test('rejects a negative target', () {
      expect(
        () => validation.validateAdjustmentTarget(-1),
        throwsArgumentError,
      );
    });
  });

  group('validateAdjustmentReason', () {
    test('accepts a non-empty reason', () {
      expect(
        () => validation.validateAdjustmentReason('Physical count correction'),
        returnsNormally,
      );
    });

    test('rejects null — required, unlike stock in/out', () {
      expect(
        () => validation.validateAdjustmentReason(null),
        throwsArgumentError,
      );
    });

    test('rejects an empty string', () {
      expect(
        () => validation.validateAdjustmentReason(''),
        throwsArgumentError,
      );
    });

    test('rejects a whitespace-only string', () {
      expect(
        () => validation.validateAdjustmentReason('   '),
        throwsArgumentError,
      );
    });
  });
}
