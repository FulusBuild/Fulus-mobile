import 'package:flutter_test/flutter_test.dart';

import 'package:fulus_mobile/core/errors/failure.dart';
import 'package:fulus_mobile/sync/sync_user_message.dart';

void main() {
  test('technical sync errors are converted to calm user language', () {
    final message = syncUserMessage(
      const BusinessRuleFailure(
        'Canonical stock movement contains an invalid date.',
        code: 'SYNC_PULL_FAILED',
      ),
    );

    expect(message, contains('Cloud backup'));
    expect(message, isNot(contains('Canonical')));
    expect(message, isNot(contains('stock movement')));
    expect(message, isNot(contains('SYNC_PULL_FAILED')));
  });

  test('conflict recovery messages stay user-facing', () {
    expect(
      syncUserMessage(
        const BusinessRuleFailure(
          'internal',
          code: 'SYNC_RECOVERY_BLOCKED_CONFLICT',
        ),
      ),
      'One change needs your review before cloud backup can continue.',
    );
  });

  test('validation failures never expose raw implementation text', () {
    final message = syncUserMessage(
      const ValidationFailure(fieldErrors: {'sync': 'Canonical stock movement contains an invalid date.'}),
    );
    expect(message, contains('Cloud backup'));
    expect(message, isNot(contains('Canonical')));
    expect(message, isNot(contains('invalid date')));
  });

  test('auth failures never expose raw session details', () {
    final message = syncUserMessage(
      const AuthFailure.sessionExpired(),
    );
    expect(message, contains('session'));
    expect(message, isNot(contains('JWT')));
    expect(message, isNot(contains('refresh token')));
  });

  test('unknown exceptions never expose their raw text', () {
    final message = syncUserMessage(StateError('foreign key constraint failed'));
    expect(message, isNot(contains('foreign key')));
    expect(message, contains('Your work is safe'));
  });

  test('entity labels hide internal entity names', () {
    expect(syncEntityLabel('stock_movement'), 'stock change');
    expect(syncEntityLabel('customer_ledger'), 'customer payment');
    expect(syncEntityLabel('unknown_internal_entity'), 'business data');
  });
}
