import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart' show dataRefreshSignalProvider;
import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../domain/cash_drawer_state.dart';
import '../providers/money_providers.dart';
import '../utils/money_format.dart';
import '../widgets/opening_float_sheet.dart';

/// Volume 8's Daily Closing, screen one — "expected, counted,
/// difference — never an interrogation." Reached from Home's Close
/// Shop action.
class DailyClosingCountScreen extends ConsumerStatefulWidget {
  const DailyClosingCountScreen({super.key});

  @override
  ConsumerState<DailyClosingCountScreen> createState() => _DailyClosingCountScreenState();
}

class _DailyClosingCountScreenState extends ConsumerState<DailyClosingCountScreen> {
  late Future<({MoneyDrawerSession? session, MoneyExpectedCashPreview? preview})> _future;
  final _countedController = TextEditingController();
  final _noteController = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _countedController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<({MoneyDrawerSession? session, MoneyExpectedCashPreview? preview})> _load() async {
    final repo = ref.read(moneyRepositoryProvider);
    final session = await repo.getActiveDrawerSession();
    if (session == null) return (session: null, preview: null);
    final preview = await repo.computeExpectedCash();
    return (session: session, preview: preview);
  }

  Future<void> _openDrawer() async {
    final opened = await showOpeningFloatSheet(context);
    if (opened && mounted) {
      setState(() {
        _future = _load();
      });
    }
  }

  Future<void> _closeDay() async {
    final counted = double.tryParse(_countedController.text.replaceAll(',', '').trim());
    if (counted == null || counted < 0) {
      showFulusSnackbar(context, message: 'Enter how much cash was actually counted.');
      return;
    }
    setState(() => _submitting = true);
    try {
      final summary = await ref.read(moneyRepositoryProvider).closeDrawer(
            countedCash: counted,
            note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
          );
      // Gap fix: Home's hero used to keep showing "open" after this —
      // see dataRefreshSignalProvider's own doc comment in
      // app/providers.dart. Bumped here, the moment the close is
      // actually committed, not on the Summary screen after — Home
      // should already be caught up by the time anyone backs out to it,
      // whether or not they view the summary all the way through.
      ref.read(dataRefreshSignalProvider.notifier).state++;
      if (!mounted) return;
      context.pushReplacementNamed('moneyDailyClosingSummary', extra: summary);
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showFulusSnackbar(context, message: "Couldn't close the day. Please try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencySymbol = ref.watch(moneyCurrencySymbolProvider).value ?? '₦';

    return FulusScreen(
      title: 'Close the day',
      body: FutureBuilder<({MoneyDrawerSession? session, MoneyExpectedCashPreview? preview})>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return FulusErrorState(
              message: "Couldn't load the drawer.",
              onRetry: () => setState(() {
                _future = _load();
              }),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: FulusLoadingIndicator());
          }
          final data = snapshot.data!;
          if (data.session == null) {
            return FulusEmptyState(
              icon: Icons.point_of_sale_outlined,
              headline: 'No drawer is open right now.',
              body: 'Open the drawer with an opening float before closing the day.',
              actionLabel: 'Open the drawer',
              onAction: _openDrawer,
            );
          }
          final preview = data.preview!;
          final counted = double.tryParse(_countedController.text.replaceAll(',', '').trim());
          final difference = counted == null ? null : counted - preview.expectedCash;

          return ListView(
            children: [
              FulusSectionHeader(title: 'Expected cash'),
              FulusCard(
                child: Column(
                  children: [
                    _AmountRow(label: 'Opening float', value: preview.openingFloat, symbol: currencySymbol),
                    _AmountRow(label: 'Cash sales', value: preview.cashSales, symbol: currencySymbol, showPlus: true),
                    _AmountRow(label: 'Cash expenses', value: -preview.cashExpenses, symbol: currencySymbol),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: Divider(height: 1),
                    ),
                    _AmountRow(
                      label: 'Expected total',
                      value: preview.expectedCash,
                      symbol: currencySymbol,
                      emphasize: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              FulusTextField(
                label: 'Cash counted',
                controller: _countedController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                hintText: '0.00',
                onChanged: (_) => setState(() {}),
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.lg),
                  child: Align(widthFactor: 1, child: Text(currencySymbol)),
                ),
              ),
              if (difference != null) ...[
                const SizedBox(height: AppSpacing.md),
                _DifferencePill(difference: difference, symbol: currencySymbol),
              ],
              const SizedBox(height: AppSpacing.lg),
              FulusTextField(label: 'Note (optional)', controller: _noteController, maxLines: 3),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: FulusButton(label: 'Close day', loading: _submitting, onPressed: _submitting ? null : _closeDay),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          );
        },
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.value,
    required this.symbol,
    this.showPlus = false,
    this.emphasize = false,
  });

  final String label;
  final double value;
  final String symbol;
  final bool showPlus;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final style = emphasize
        ? AppTypography.subheading.copyWith(color: AppColors.textPrimaryOf(context), fontFeatures: const [FontFeature.tabularFigures()])
        : AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context), fontFeatures: const [FontFeature.tabularFigures()]);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: (emphasize ? AppTypography.subheading : AppTypography.body).copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          Text(formatMoney(value, symbol: symbol, showSign: showPlus || value < 0), style: style),
        ],
      ),
    );
  }
}

class _DifferencePill extends StatelessWidget {
  const _DifferencePill({required this.difference, required this.symbol});
  final double difference;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final matches = difference == 0;
    final color = matches ? AppColors.primaryOf(context) : AppColors.warningOf(context);
    final label = matches
        ? 'Matches exactly'
        : difference > 0
            ? '${formatMoney(difference, symbol: symbol)} more than expected'
            : '${formatMoney(-difference, symbol: symbol)} short';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Icon(matches ? Icons.check_circle_outline : Icons.info_outline, size: AppIconSize.compact, color: color),
          const SizedBox(width: AppSpacing.sm),
          Text(label, style: AppTypography.body.copyWith(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
