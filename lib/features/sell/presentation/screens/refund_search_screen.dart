import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/formatting.dart';
import '../../../../domain/entities/customer.dart';
import '../../../../domain/entities/sale.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../money/presentation/providers/money_providers.dart'
    show moneyCurrencySymbolProvider, moneyCustomersProvider;

/// Gap fix: refunds had a complete backend (ReturnRepository — create,
/// approve/reject, complete, eligibility) and zero UI. This screen and
/// RefundConfirmScreen are that missing UI, matching Volume 5's Refund
/// Search / Refund Confirm pair.
///
/// No dedicated sale-search method exists on SaleRepository (only
/// getSalesForPeriod, watchSalesForToday, getSaleByLocalId) — this
/// fetches the last 30 days for the active location and filters
/// client-side, the same trade-off Reports' own period-scoped fetching
/// already makes elsewhere in this app.
class RefundSearchScreen extends ConsumerStatefulWidget {
  const RefundSearchScreen({super.key});

  @override
  ConsumerState<RefundSearchScreen> createState() => _RefundSearchScreenState();
}

class _RefundSearchScreenState extends ConsumerState<RefundSearchScreen> {
  late Future<List<Sale>> _future;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Sale>> _load() async {
    final locationId = await ref.read(activeLocationIdProvider.future);
    final now = DateTime.now();
    final sales = await ref.read(saleRepositoryProvider).getSalesForPeriod(
          locationId: locationId,
          start: now.subtract(const Duration(days: 30)),
          end: now,
        );
    return sales.reversed.toList(); // most recent first
  }

  @override
  Widget build(BuildContext context) {
    final currencySymbol = ref.watch(moneyCurrencySymbolProvider).value ?? '₦';
    // UX fix: this used to only match on invoice number, though Volume
    // 5 names receipt number OR customer as valid ways to find a sale —
    // a cashier who remembers who bought something but not the receipt
    // number had no way to find it. Sale itself only carries a
    // customerId (no denormalized name), so this builds a small lookup
    // from the same customer list the Credit Book already watches.
    final customerNameById = <String, String>{
      for (final c in ref.watch(moneyCustomersProvider).value ?? const <Customer>[]) c.localId: c.name,
    };

    return FulusScreen(
      title: 'Find a sale to refund',
      applyPadding: false,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
            child: FulusSearchField(
              controller: _searchController,
              hintText: 'Search by receipt number or customer…',
              onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
              onClear: () => setState(() => _query = ''),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Sale>>(
              future: _future,
              builder: (context, snap) {
                if (snap.hasError) {
                  return FulusErrorState(
                    message: "Couldn't load recent sales.",
                    onRetry: () => setState(() {
                      _future = _load();
                    }),
                  );
                }
                if (!snap.hasData) {
                  return const FulusLoadingIndicator();
                }
                var sales = snap.data!;
                if (_query.isNotEmpty) {
                  sales = sales.where((s) {
                    final invoice = (s.invoiceNumber ?? s.localId).toLowerCase();
                    final customerName = (s.customerId != null ? customerNameById[s.customerId] : null)?.toLowerCase();
                    return invoice.contains(_query) || (customerName?.contains(_query) ?? false);
                  }).toList();
                }
                if (sales.isEmpty) {
                  return FulusEmptyState(
                    icon: Icons.receipt_long_outlined,
                    headline: _query.isEmpty ? 'No sales in the last 30 days.' : 'No matching sales found.',
                    body: _query.isEmpty ? null : 'Try a different receipt number.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: sales.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, i) {
                    final sale = sales[i];
                    return FulusCard(
                      onTap: () => context.pushNamed('sellRefundConfirm', pathParameters: {'saleId': sale.localId}),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  sale.invoiceNumber ?? 'Sale #${sale.localId.substring(0, 8)}',
                                  style: AppTypography.body
                                      .copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimaryOf(context)),
                                ),
                                Text(
                                  '${formatRelativeDay(sale.saleDate)} · ${sale.items.length} item${sale.items.length == 1 ? '' : 's'}'
                                  '${sale.customerId != null && customerNameById[sale.customerId] != null ? ' · ${customerNameById[sale.customerId]}' : ''}',
                                  style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            formatMoney(sale.total, symbol: currencySymbol),
                            style: AppTypography.body.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimaryOf(context)),
                          ),
                          Icon(Icons.chevron_right, color: AppColors.textSecondaryOf(context)),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

}
