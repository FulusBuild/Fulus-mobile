import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';
import '../providers/money_providers.dart';
import '../utils/money_format.dart';
import '../widgets/supplier_form_sheet.dart';

/// Volume 8, Decision 26: "A supplier's balance works exactly like the
/// customer credit book, mirrored." Real data — `SupplierRepository`
/// needs no locationId and is already fully implemented.
///
/// Bug fix (suppliers gap-closure): this screen never actually gave
/// anyone a way to call that repository's `createSupplier` — no button
/// anywhere opened a form, matching `CustomersListScreen`'s own "Add
/// customer" action. That's why no supplier profile was ever reachable
/// either: there was no way to create the supplier a profile would be
/// for.
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
      applyPadding: false,
      actions: [
        FulusIconButton(
          icon: Icons.add_business_outlined,
          tooltip: 'Add supplier',
          onPressed: () => SupplierFormSheet.show(context),
        ),
      ],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
            child: FulusSearchField(
              hintText: 'Search suppliers',
              onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: suppliersAsync.when(
              loading: () => const FulusDelayedSkeleton(
                skeleton: Column(children: [
                  FulusListRowSkeleton(),
                  FulusListRowSkeleton(),
                  FulusListRowSkeleton(),
                  FulusListRowSkeleton(),
                  FulusListRowSkeleton(),
                  FulusListRowSkeleton(),
                ]),
              ),
              error: (error, stack) => FulusErrorState(
                message: "Couldn't load your suppliers.",
                reassurance: 'Nothing has been lost — this is only about showing the list right now.',
                onRetry: () => ref.invalidate(moneySuppliersProvider),
              ),
              data: (suppliers) {
                final filtered =
                    _query.isEmpty ? suppliers : suppliers.where((s) => s.name.toLowerCase().contains(_query)).toList();
                if (suppliers.isEmpty) {
                  return SingleChildScrollView(
                    child: FulusEmptyState(
                      icon: Icons.local_shipping_outlined,
                      headline: 'No suppliers yet.',
                      body: 'Suppliers you owe for stock bought on credit will show up here, with a running balance.',
                      actionLabel: 'Add supplier',
                      onAction: () => SupplierFormSheet.show(context),
                    ),
                  );
                }
                if (filtered.isEmpty) {
                  return const SingleChildScrollView(
                    child: FulusEmptyState(icon: Icons.search_off, headline: 'No suppliers match your search.'),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const FulusListDivider(),
                  itemBuilder: (context, index) {
                    final supplier = filtered[index];
                    return FulusListRow(
                      leading: Container(
                        decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.surfaceAltOf(context)),
                        child: Center(
                          child: Icon(Icons.local_shipping_outlined, color: AppColors.textSecondaryOf(context)),
                        ),
                      ),
                      title: Text(supplier.name),
                      subtitle: Text(supplier.phone ?? 'No phone number'),
                      trailing: Text(
                        formatMoney(supplier.outstandingBalance, symbol: currencySymbol),
                        style: AppTypography.body.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                          fontWeight: FontWeight.w600,
                          color: supplier.outstandingBalance > 0
                              ? AppColors.textPrimaryOf(context)
                              : AppColors.textSecondaryOf(context),
                        ),
                      ),
                      onTap: () => context.pushNamed(
                        'moneySupplierProfile',
                        pathParameters: {'id': supplier.localId},
                        extra: supplier,
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
