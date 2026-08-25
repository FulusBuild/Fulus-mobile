import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/export/export_service.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../domain/cash_drawer_state.dart';
import '../providers/money_providers.dart';
import '../utils/money_format.dart';

/// Volume 8's Daily Closing, screen two — "what Home's 'Closed' state
/// is quietly reflecting," plus the by-payment-method sales split
/// ("'Paid with' isn't a formality").
class DailyClosingSummaryScreen extends ConsumerWidget {
  const DailyClosingSummaryScreen({super.key, required this.summary});

  final DailyClosingSummary summary;

  Future<void> _export(BuildContext context, WidgetRef ref, String currencySymbol) async {
    try {
      await ref.read(exportServiceProvider).export(
            format: ExportFormat.pdf,
            fileName: 'daily-closing-${summary.closedAt.millisecondsSinceEpoch}',
            title: 'Daily closing summary',
            subtitle: '${formatRelativeDay(summary.closedAt)} · ${formatTime(summary.closedAt)}',
            headers: const ['Item', 'Amount'],
            rows: [
              for (final entry in summary.salesByMethod.entries)
                ['Sales — ${entry.key}', formatMoney(entry.value, symbol: currencySymbol)],
              ['Total sales', formatMoney(summary.totalSales, symbol: currencySymbol)],
              ['Expenses', formatMoney(summary.expensesTotal, symbol: currencySymbol)],
              ['Net for the day', formatMoney(summary.netForDay, symbol: currencySymbol, showSign: true)],
              ['Expected cash', formatMoney(summary.expectedCash, symbol: currencySymbol)],
              ['Counted cash', formatMoney(summary.countedCash, symbol: currencySymbol)],
              ['Difference', formatMoney(summary.difference, symbol: currencySymbol, showSign: true)],
              if (summary.note != null) ['Note', summary.note!],
            ],
          );
    } catch (_) {
      if (context.mounted) showFulusSnackbar(context, message: "Couldn't export this summary right now.");
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currencySymbol = ref.watch(moneyCurrencySymbolProvider).value ?? '₦';
    final matches = summary.difference == 0;

    return FulusScreen(
      title: 'Day closed',
      body: ListView(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primaryOf(context).withValues(alpha: 0.12)),
                  child: Icon(Icons.check_circle_outline, size: AppIconSize.base, color: AppColors.primaryOf(context)),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  formatMoney(summary.netForDay, symbol: currencySymbol, showSign: true),
                  style: AppTypography.display.copyWith(
                    color: summary.netForDay >= 0 ? AppColors.primaryOf(context) : AppColors.textPrimaryOf(context),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text('Net for the day', style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
              ],
            ),
          ),
          if (summary.salesByMethod.isNotEmpty) ...[
            FulusSectionHeader(title: 'Sales — paid with'),
            FulusCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < summary.salesByMethod.length; i++) ...[
                    if (i > 0) const FulusListDivider(indented: false),
                    _Row(
                      label: summary.salesByMethod.keys.elementAt(i),
                      value: summary.salesByMethod.values.elementAt(i),
                      symbol: currencySymbol,
                    ),
                  ],
                  const FulusListDivider(indented: false),
                  _Row(label: 'Total sales', value: summary.totalSales, symbol: currencySymbol, emphasize: true),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          FulusSectionHeader(title: 'Cash drawer'),
          FulusCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _Row(label: 'Expenses', value: -summary.expensesTotal, symbol: currencySymbol),
                const FulusListDivider(indented: false),
                _Row(label: 'Expected cash', value: summary.expectedCash, symbol: currencySymbol),
                const FulusListDivider(indented: false),
                _Row(label: 'Counted cash', value: summary.countedCash, symbol: currencySymbol),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: (matches ? AppColors.primaryOf(context) : AppColors.warningOf(context)).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Row(
              children: [
                Icon(
                  matches ? Icons.check_circle_outline : Icons.info_outline,
                  size: AppIconSize.compact,
                  color: matches ? AppColors.primaryOf(context) : AppColors.warningOf(context),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  matches ? 'Cash matched exactly' : '${formatMoney(summary.difference.abs(), symbol: currencySymbol)} ${summary.difference > 0 ? 'over' : 'short'}',
                  style: AppTypography.body.copyWith(
                    color: matches ? AppColors.primaryOf(context) : AppColors.warningOf(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (summary.note != null) ...[
            const SizedBox(height: AppSpacing.lg),
            FulusSectionHeader(title: 'Note'),
            FulusCard(child: Text(summary.note!, style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context)))),
          ],
          const SizedBox(height: AppSpacing.xl),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FulusButton(
                    label: 'Export summary',
                    icon: Icons.ios_share,
                    variant: FulusButtonVariant.secondary,
                    onPressed: () => _export(context, ref, currencySymbol),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: FulusButton(
                    label: 'Done',
                    onPressed: () => context.goNamed('money'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, required this.symbol, this.emphasize = false});
  final String label;
  final double value;
  final String symbol;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTypography.body.copyWith(
              color: emphasize ? AppColors.textPrimaryOf(context) : AppColors.textSecondaryOf(context),
              fontWeight: emphasize ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          Text(
            formatMoney(value, symbol: symbol, showSign: value < 0),
            style: AppTypography.body.copyWith(
              color: AppColors.textPrimaryOf(context),
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
