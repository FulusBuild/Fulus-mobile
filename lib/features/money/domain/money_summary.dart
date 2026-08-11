import '../../../domain/entities/report.dart';
import 'money_transaction.dart';

/// One line of a breakdown list — "Sales income ₦82,400", "Rent
/// ₦150,000" — Volume 8's Cash Flow screen: "MONEY IN BREAKDOWN /
/// MONEY OUT BREAKDOWN, each row tappable through to the transactions
/// behind it." [type] (plus [label] doubling as the expense category,
/// for expense rows specifically) is what a tap uses to filter History
/// down to exactly the transactions this row summarizes — see
/// `MoneyRepository.getTransactions`'s `category` parameter.
class CategoryTotal {
  const CategoryTotal({required this.label, required this.amount, required this.count, this.type});
  final String label;
  final double amount;
  final int count;
  final MoneyTransactionType? type;
}

/// Volume 8's Cash Flow screen, for one resolved [period]: "Money In,
/// Money Out, and Net, for a selected period — one view, not a chart
/// wall." [incomeBreakdown]/[expenseBreakdown] back the two breakdown
/// sections underneath.
class MoneySummary {
  const MoneySummary({
    required this.period,
    required this.moneyIn,
    required this.moneyOut,
    required this.previousNet,
    required this.incomeBreakdown,
    required this.expenseBreakdown,
    required this.transactionCount,
  });

  final ReportPeriod period;
  final double moneyIn;
  final double moneyOut;
  double get net => moneyIn - moneyOut;

  /// Net for the immediately-preceding period of the same length —
  /// what the hero's trend arrow compares against, same "vs previous
  /// period of equal length" rule Reports' Finance tab already uses.
  final double previousNet;

  final List<CategoryTotal> incomeBreakdown;
  final List<CategoryTotal> expenseBreakdown;
  final int transactionCount;
}
