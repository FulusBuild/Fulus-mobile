import '../core/errors/failure.dart';

/// Converts sync failures into calm, user-facing language.
///
/// Detailed error codes/messages remain available to diagnostics and logs.
/// Normal business UI should never expose transport, database, cursor, or
/// reconciliation terminology.
String syncUserMessage(Object error) {
  if (error is Failure) {
    final code = error is BusinessRuleFailure ? error.code : null;
    switch (code) {
      case 'SYNC_CURSOR_TOO_OLD':
        return 'Cloud backup needs to catch up. Fulus will restore it automatically.';
      case 'SYNC_CONFLICT_PENDING':
      case 'SYNC_RECOVERY_BLOCKED_CONFLICT':
        return 'One change needs your review before cloud backup can continue.';
      case 'SYNC_RECOVERY_BLOCKED_PENDING':
        return 'Fulus is finishing an earlier backup before restoring cloud history.';
      case 'IDEMPOTENCY_CONFLICT':
        return 'A backup change could not be applied safely. Your work is still safe on this device.';
      case 'SYNC_CURSOR_CHECK_FAILED':
      case 'SYNC_PULL_FAILED':
      case 'SYNC_RECOVERY_FAILED':
        return 'Cloud backup is temporarily unavailable. Fulus will keep trying automatically.';
    }

    // These Failure messages are already deliberately written for users.
    if (error is NetworkFailure) {
      return 'Cloud backup is temporarily unavailable. Your work is safe on this device. Fulus will retry automatically.';
    }
    if (error is AuthFailure) {
      return 'Your session needs to reconnect. Your work is safe on this device.';
    }
    if (error is ValidationFailure) {
      return 'Cloud backup could not accept a change. Your work is safe on this device. Fulus will keep trying automatically.';
    }
  }

  return 'Cloud backup is temporarily unavailable. Your work is safe on this device. Fulus will keep trying automatically.';
}

/// Turns internal entity names into ordinary business language.
String syncEntityLabel(String entityType) => switch (entityType) {
      'product' => 'product',
      'category' => 'category',
      'supplier' => 'supplier',
      'location' => 'location',
      'customer' => 'customer',
      'customer_ledger' => 'customer payment',
      'sale' => 'sale',
      'return' => 'return',
      'stock_movement' => 'stock change',
      'expense_category' => 'expense category',
      'expense' => 'expense',
      'income_record' => 'income',
      'cash_drawer_shift' => 'cash drawer',
      _ => 'business data',
    };
