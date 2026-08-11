import 'money_transaction.dart';

/// Carried via `GoRouterState.extra` when navigating into Money History
/// from a tapped `MoneyBreakdownSection` row, so History opens already
/// filtered to exactly the transactions that row summarized — Volume
/// 8: "each row tappable through to the actual list of transactions
/// behind it."
class MoneyHistoryFilterRequest {
  const MoneyHistoryFilterRequest({this.type, this.category});

  final MoneyTransactionType? type;

  /// Only meaningful alongside `type: MoneyTransactionType.expense`.
  final String? category;
}
