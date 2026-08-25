import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/providers.dart';
import '../../../../../core/theme/design_tokens.dart';
import '../../../../../core/utils/formatting.dart';
import '../../../../../domain/entities/report.dart';
import '../../../../../shared/widgets/widgets.dart';
import '../../../../money/presentation/providers/money_providers.dart' show moneyCurrencySymbolProvider;

/// The Sales report's drill-down screen — "revenue → sales transactions
/// → individual sale → ... → payment → customer → cashier/user →
/// timestamp → receipt/reference" from the brief, made real. Reads
/// [SalesReport.transactions] for the same [period] the summary card
/// was tapped from, rather than re-querying with different logic —
/// the list and the total it drilled down from can't disagree.
class SalesTransactionsScreen extends ConsumerStatefulWidget {
  const SalesTransactionsScreen({super.key, required this.period});
  final ReportPeriod period;

  @override
  ConsumerState<SalesTransactionsScreen> createState() => _SalesTransactionsScreenState();
}

class _SalesTransactionsScreenState extends ConsumerState<SalesTransactionsScreen> {
  late Future<SalesReport> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(reportsRepositoryProvider).getSalesReport(widget.period);
  }

  @override
  Widget build(BuildContext context) {
    final currencySymbol = ref.watch(moneyCurrencySymbolProvider).value ?? '₦';

    return FulusScreen(
      title: 'Sales transactions',
      body: FutureBuilder<SalesReport>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return FulusErrorState(
              message: "Couldn't load these transactions.",
              onRetry: () => setState(() {
                _future = ref.read(reportsRepositoryProvider).getSalesReport(widget.period);
              }),
            );
          }
          if (!snap.hasData) {
            return const FulusLoadingIndicator();
          }
          final transactions = snap.data!.transactions;
          if (transactions.isEmpty) {
            return FulusEmptyState(
              icon: Icons.receipt_long_outlined,
              headline: 'No sales in this period.',
              body: 'Sales you record will show up here.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: transactions.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) => _SaleRecordCard(
              record: transactions[i],
              currencySymbol: currencySymbol,
              onTap: () => _showDetail(context, transactions[i]),
            ),
          );
        },
      ),
    );
  }

  /// A row tap opens this — a plain, view-only summary of the record
  /// already on screen, not an immediate jump into an action. Void is
  /// one explicit tap further from here, and only offered at all when
  /// the sale is still in a voidable state — browsing the report and
  /// accidentally landing on "confirm void" was the wrong shape for a
  /// screen whose whole purpose is auditability, not action.
  void _showDetail(BuildContext context, SaleRecord record) {
    showFulusBottomSheet<void>(
      context: context,
      title: record.invoiceNumber ?? record.saleLocalId,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DetailRow(label: 'Date', value: '${formatRelativeDay(record.saleDate)} · ${formatTime(record.saleDate)}'),
          if (record.customerName != null) _DetailRow(label: 'Customer', value: record.customerName!),
          if (record.cashierName != null) _DetailRow(label: 'Cashier', value: record.cashierName!),
          if (record.paymentMethod != null) _DetailRow(label: 'Payment method', value: record.paymentMethod!),
          _DetailRow(
            label: 'Total',
            value: formatMoney(record.total, symbol: ref.read(moneyCurrencySymbolProvider).value ?? '₦'),
          ),
          if (record.discount > 0)
            _DetailRow(
              label: 'Discount',
              value: formatMoney(record.discount, symbol: ref.read(moneyCurrencySymbolProvider).value ?? '₦'),
            ),
          if (record.status == SaleRecordStatus.completed) ...[
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FulusButton(
                label: 'Void this sale',
                variant: FulusButtonVariant.destructive,
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  context.pushNamed('moreReportsVoidSale', pathParameters: {'saleId': record.saleLocalId});
                },
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context))),
          ),
          Text(
            value,
            style: AppTypography.body.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimaryOf(context)),
          ),
        ],
      ),
    );
  }
}

class _SaleRecordCard extends StatelessWidget {
  const _SaleRecordCard({required this.record, required this.currencySymbol, required this.onTap});
  final SaleRecord record;
  final String currencySymbol;
  final VoidCallback onTap;

  ({String label, FulusStatusTone tone}) get _status {
    switch (record.status) {
      case SaleRecordStatus.completed:
        return (label: 'Completed', tone: FulusStatusTone.positive);
      case SaleRecordStatus.partiallyRefunded:
        return (label: 'Partially refunded', tone: FulusStatusTone.warning);
      case SaleRecordStatus.refunded:
        return (label: 'Refunded', tone: FulusStatusTone.neutral);
      case SaleRecordStatus.voided:
        return (label: 'Voided', tone: FulusStatusTone.warning);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return FulusCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  record.invoiceNumber ?? record.saleLocalId,
                  style: AppTypography.body.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimaryOf(context)),
                ),
              ),
              Text(
                formatMoney(record.total, symbol: currencySymbol),
                style: AppTypography.body.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimaryOf(context)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${formatRelativeDay(record.saleDate)} · ${formatTime(record.saleDate)}',
            style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
          ),
          if (record.customerName != null || record.cashierName != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              [
                if (record.customerName != null) record.customerName!,
                if (record.cashierName != null) 'Sold by ${record.cashierName}',
              ].join(' · '),
              style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              if (record.paymentMethod != null) ...[
                FulusStatusPill(label: record.paymentMethod!, tone: FulusStatusTone.neutral),
                const SizedBox(width: AppSpacing.xs),
              ],
              FulusStatusPill(label: status.label, tone: status.tone),
              if (record.discount > 0) ...[
                const SizedBox(width: AppSpacing.xs),
                FulusStatusPill(
                  label: '${formatMoney(record.discount, symbol: currencySymbol)} off',
                  tone: FulusStatusTone.neutral,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
