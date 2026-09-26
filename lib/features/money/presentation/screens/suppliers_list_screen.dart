import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/supplier.dart';
import '../../../../shared/widgets/widgets.dart';
import '../providers/money_providers.dart';
import '../utils/money_format.dart';
import '../widgets/supplier_form_sheet.dart';

/// Suppliers mirror the customer credit book. This pass modernizes the
/// presentation without changing repository or payment behavior.
class SuppliersListScreen extends ConsumerStatefulWidget {
  const SuppliersListScreen({super.key});

  @override
  ConsumerState<SuppliersListScreen> createState() => _SuppliersListScreenState();
}

class _SuppliersListScreenState extends ConsumerState<SuppliersListScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final suppliersAsync = ref.watch(moneySuppliersProvider);
    final currencySymbol = ref.watch(moneyCurrencySymbolProvider).value ?? '₦';

    return FulusScreen(
      title: 'Suppliers',
      subtitle: 'People and businesses you buy from',
      actions: [
        FulusIconButton(
          icon: Icons.add_business_outlined,
          tooltip: 'Add supplier',
          onPressed: () => SupplierFormSheet.show(context),
        ),
      ],
      body: suppliersAsync.when(
        loading: () => const FulusDelayedSkeleton(
          skeleton: Column(
            children: [
              FulusSkeletonBox(height: 96),
              SizedBox(height: AppSpacing.lg),
              FulusListRowSkeleton(),
              FulusListRowSkeleton(),
              FulusListRowSkeleton(),
              FulusListRowSkeleton(),
            ],
          ),
        ),
        error: (error, stack) => FulusErrorState(
          message: "Couldn't load your suppliers.",
          reassurance: 'Nothing has been lost — this is only about showing the list right now.',
          onRetry: () => ref.invalidate(moneySuppliersProvider),
        ),
        data: (suppliers) {
          final filtered = _filter(suppliers);
          final outstanding = suppliers.fold<double>(0, (sum, supplier) => sum + supplier.outstandingBalance);
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              final inset = wide ? AppSpacing.lg : AppSpacing.sm;
              return ListView(
                padding: EdgeInsets.fromLTRB(inset, AppSpacing.sm, inset, AppSpacing.xxl),
                children: [
                  _SupplierOverview(count: suppliers.length, outstanding: outstanding, currencySymbol: currencySymbol),
                  const SizedBox(height: AppSpacing.lg),
                  FulusSearchField(
                    hintText: 'Search by name or phone',
                    onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (suppliers.isEmpty)
                    FulusEmptyState(
                      icon: Icons.local_shipping_outlined,
                      headline: 'No suppliers yet',
                      body: 'Suppliers you owe for stock bought on credit will show up here, with a running balance.',
                      actionLabel: 'Add supplier',
                      onAction: () => SupplierFormSheet.show(context),
                    )
                  else if (filtered.isEmpty)
                    const FulusEmptyState(
                      icon: Icons.search_off,
                      headline: 'No suppliers match your search',
                      body: 'Try a different name or phone number.',
                    )
                  else
                    FulusCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0; i < filtered.length; i++) ...[
                            _SupplierRow(supplier: filtered[i], currencySymbol: currencySymbol),
                            if (i < filtered.length - 1) const FulusListDivider(),
                          ],
                        ],
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  List<Supplier> _filter(List<Supplier> suppliers) {
    if (_query.isEmpty) return suppliers;
    return suppliers.where((supplier) {
      final name = supplier.name.toLowerCase();
      final phone = (supplier.phone ?? '').toLowerCase();
      return name.contains(_query) || phone.contains(_query);
    }).toList();
  }
}

class _SupplierOverview extends StatelessWidget {
  const _SupplierOverview({required this.count, required this.outstanding, required this.currencySymbol});

  final int count;
  final double outstanding;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.textScalerOf(context).scale(1) > 1.15;
    return FulusCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = compact || constraints.maxWidth < 420;
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Metric(icon: Icons.local_shipping_outlined, label: 'Suppliers', value: '$count'),
                const SizedBox(height: AppSpacing.lg),
                Divider(height: 1, color: AppColors.borderOf(context)),
                const SizedBox(height: AppSpacing.lg),
                _Metric(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Outstanding',
                  value: formatMoney(outstanding, symbol: currencySymbol),
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: _Metric(icon: Icons.local_shipping_outlined, label: 'Suppliers', value: '$count')),
              const SizedBox(width: AppSpacing.lg),
              Container(width: 1, height: 44, color: AppColors.borderOf(context)),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                flex: 2,
                child: _Metric(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Outstanding',
                  value: formatMoney(outstanding, symbol: currencySymbol),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.selectedTintOf(context), borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Icon(icon, color: AppColors.primaryOf(context)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
                const SizedBox(height: 2),
                FittedBox(alignment: Alignment.centerLeft, fit: BoxFit.scaleDown, child: Text(value, style: AppTypography.subheading.copyWith(color: AppColors.textPrimaryOf(context), fontWeight: FontWeight.w700))),
              ],
            ),
          ),
        ],
      );
}

class _SupplierRow extends StatelessWidget {
  const _SupplierRow({required this.supplier, required this.currencySymbol});
  final Supplier supplier;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final outstanding = supplier.outstandingBalance;
    return FulusListRow(
      leading: FulusAvatar(name: supplier.name),
      title: Text(supplier.name),
      subtitle: Text(supplier.phone ?? 'No phone number'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            formatMoney(outstanding, symbol: currencySymbol),
            style: AppTypography.body.copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          Text(outstanding > 0 ? 'Outstanding' : 'Settled', style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
        ],
      ),
      onTap: () => context.pushNamed('moneySupplierProfile', pathParameters: {'id': supplier.localId}, extra: supplier),
    );
  }
}
