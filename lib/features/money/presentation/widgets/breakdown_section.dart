import 'package:flutter/material.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../domain/money_summary.dart';
import '../utils/money_format.dart';

/// "MONEY IN BREAKDOWN" / "MONEY OUT BREAKDOWN" — Volume 8's Cash Flow
/// screen, "each row tappable through to the actual list of
/// transactions behind it" ([onRowTap]).
class MoneyBreakdownSection extends StatelessWidget {
  const MoneyBreakdownSection({
    super.key,
    required this.title,
    required this.rows,
    required this.currencySymbol,
    this.amountColor,
    this.onRowTap,
  });

  final String title;
  final List<CategoryTotal> rows;
  final String currencySymbol;
  final Color? amountColor;
  final ValueChanged<CategoryTotal>? onRowTap;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FulusSectionHeader(title: title),
        FulusCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const FulusListDivider(indented: false),
                FulusListRow(
                  title: Text(rows[i].label),
                  subtitle: Text('${rows[i].count} transaction${rows[i].count == 1 ? '' : 's'}'),
                  trailing: Text(
                    formatMoney(rows[i].amount, symbol: currencySymbol),
                    style: AppTypography.body.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      fontWeight: FontWeight.w600,
                      color: amountColor ?? AppColors.textPrimaryOf(context),
                    ),
                  ),
                  onTap: onRowTap == null ? null : () => onRowTap!(rows[i]),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}
