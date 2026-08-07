import 'package:test/test.dart';

import 'package:fulus_mobile/core/business_engine/customer_credit_engine.dart';

void main() {
  group('checkCreditLimitWarning', () {
    test('no warning when no limit is set', () {
      expect(
        checkCreditLimitWarning(
          currentBalance: 50000,
          proposedAdditionalCredit: 100000,
          creditLimit: null,
        ),
        isNull,
      );
    });

    test('no warning when the projected balance stays within the limit', () {
      expect(
        checkCreditLimitWarning(
          currentBalance: 3000,
          proposedAdditionalCredit: 2000,
          creditLimit: 10000,
        ),
        isNull,
      );
    });

    test('no warning when the projected balance lands exactly on the limit',
        () {
      expect(
        checkCreditLimitWarning(
          currentBalance: 8000,
          proposedAdditionalCredit: 2000,
          creditLimit: 10000,
        ),
        isNull,
      );
    });

    test('returns the exact overage when the limit would be exceeded', () {
      expect(
        checkCreditLimitWarning(
          currentBalance: 9000,
          proposedAdditionalCredit: 5000,
          creditLimit: 10000,
        ),
        4000,
      );
    });
  });

  group('hasReachedLoyaltyThreshold', () {
    test('false when no threshold is set', () {
      expect(
        hasReachedLoyaltyThreshold(purchaseCount: 10, loyaltyThreshold: null),
        isFalse,
      );
    });

    test('true exactly at the threshold', () {
      expect(
        hasReachedLoyaltyThreshold(purchaseCount: 10, loyaltyThreshold: 10),
        isTrue,
      );
    });

    test('true again at the next multiple — no reset needed', () {
      expect(
        hasReachedLoyaltyThreshold(purchaseCount: 20, loyaltyThreshold: 10),
        isTrue,
      );
    });

    test('false between multiples', () {
      expect(
        hasReachedLoyaltyThreshold(purchaseCount: 15, loyaltyThreshold: 10),
        isFalse,
      );
    });

    test('false at zero purchases', () {
      expect(
        hasReachedLoyaltyThreshold(purchaseCount: 0, loyaltyThreshold: 10),
        isFalse,
      );
    });
  });

  group('computeRepaymentEffect', () {
    test('a repayment smaller than the balance just reduces it', () {
      final result = computeRepaymentEffect(
        currentBalance: 10000,
        repaymentAmount: 4000,
      );
      expect(result.newBalance, 6000);
      expect(result.excessAmount, 0.0);
    });

    test('a repayment equal to the balance zeroes it out cleanly', () {
      final result = computeRepaymentEffect(
        currentBalance: 5000,
        repaymentAmount: 5000,
      );
      expect(result.newBalance, 0.0);
      expect(result.excessAmount, 0.0);
    });

    test(
        'a repayment larger than the balance caps at zero and flags the '
        'excess (Volume 7 failure scenario)', () {
      final result = computeRepaymentEffect(
        currentBalance: 3000,
        repaymentAmount: 5000,
      );
      expect(result.newBalance, 0.0);
      expect(result.excessAmount, 2000);
    });
  });
}
