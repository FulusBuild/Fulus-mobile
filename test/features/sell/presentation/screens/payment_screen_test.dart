import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/features/sell/presentation/screens/payment_screen.dart';

void main() {
  group('isPaymentSplitActive', () {
    test('does not enter split mode for a fully paid normal sale', () {
      expect(
        isPaymentSplitActive(
          explicitlySplit: false,
          paymentCount: 1,
          remaining: 0,
        ),
        isFalse,
      );
    });

    test('enters split mode when a payment leaves a positive balance', () {
      expect(
        isPaymentSplitActive(
          explicitlySplit: false,
          paymentCount: 1,
          remaining: 500,
        ),
        isTrue,
      );
    });

    test('enters split mode immediately when the user explicitly selects it', () {
      expect(
        isPaymentSplitActive(
          explicitlySplit: true,
          paymentCount: 0,
          remaining: 1000,
        ),
        isTrue,
      );
    });
  });
}
