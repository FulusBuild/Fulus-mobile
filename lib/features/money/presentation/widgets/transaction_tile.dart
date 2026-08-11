import 'package:flutter/material.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../domain/money_transaction.dart';
import '../utils/money_format.dart';

/// The type/category icon for a [MoneyTransaction] — shared between
/// this tile and the transaction detail screen's own header, so a
/// transaction shows the identical glyph everywhere it appears.
IconData moneyTransactionIcon(MoneyTransaction t) {
  switch (t.type) {
    case MoneyTransactionType.saleIncome:
      return Icons.point_of_sale_outlined;
    case MoneyTransactionType.manualIncome:
      return Icons.add_circle_outline;
    case MoneyTransactionType.customerRepayment:
      return Icons.person_outline;
    case MoneyTransactionType.supplierPayment:
      return Icons.local_shipping_outlined;
    case MoneyTransactionType.expense:
      switch (t.category) {
        case 'Rent':
          return Icons.home_outlined;
        case 'Wages':
          return Icons.people_outline;
        case 'Utilities':
          return Icons.bolt_outlined;
        case 'Transport':
          return Icons.local_shipping_outlined;
        default:
          return Icons.receipt_long_outlined;
      }
  }
}

/// One row in the Cash Flow feed — Recent Transactions, Money History,
/// and (as a read-only header) Transaction Detail all build on this
/// same tile so a transaction looks identical everywhere it appears.
class MoneyTransactionTile extends StatelessWidget {
  const MoneyTransactionTile({
    super.key,
    required this.transaction,
    required this.currencySymbol,
    this.showDate = true,
    this.onTap,
  });

  final MoneyTransaction transaction;
  final String currencySymbol;

  /// False when the caller already groups rows under a day header
  /// (Money History) — the subtitle then only needs the time.
  final bool showDate;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final timeLabel = formatTime(t.dateTime);
    final subtitleParts = <String>[
      if (showDate) formatRelativeDay(t.dateTime),
      timeLabel,
      if (t.paymentMethod != null) t.paymentMethod!,
    ];

    return FulusListRow(
      leading: Container(
        decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.surfaceAltOf(context)),
        child: Center(
          child: Icon(
            moneyTransactionIcon(t),
            size: AppIconSize.compact,
            color: t.isInflow ? AppColors.primaryOf(context) : AppColors.textSecondaryOf(context),
          ),
        ),
      ),
      title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitleParts.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(
        formatMoney(t.signedAmount, symbol: currencySymbol, showSign: true),
        style: AppTypography.body.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
          fontWeight: FontWeight.w600,
          color: t.isInflow ? AppColors.primaryOf(context) : AppColors.textPrimaryOf(context),
        ),
      ),
      onTap: onTap,
    );
  }
}
