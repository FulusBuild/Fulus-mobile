import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/customer.dart';
import '../../../../shared/widgets/widgets.dart';
import '../providers/money_providers.dart';
import '../utils/money_format.dart';

/// Volume 7: "No tab of their own — customers live inside Money." Real
/// data throughout — `CustomerRepository` needs no locationId and is
/// already fully implemented, unlike the Cash Flow side of this
/// feature.
class CustomersListScreen extends ConsumerStatefulWidget {
  const CustomersListScreen({super.key});

  @override
  ConsumerState<CustomersListScreen> createState() => _CustomersListScreenState();
}

class _CustomersListScreenState extends ConsumerState<CustomersListScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(moneyCustomersProvider);
    final currencySymbol = ref.watch(moneyCurrencySymbolProvider).valueOrNull ?? '₦';

    return FulusScreen(
      title: 'Customers',
      applyPadding: false,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
            child: FulusSearchField(
              hintText: 'Search customers',
              onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: customersAsync.when(
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
                message: "Couldn't load your customers.",
                reassurance: 'Nothing on the credit book has been lost — this is only about showing the list right now.',
                onRetry: () => ref.invalidate(moneyCustomersProvider),
              ),
              data: (customers) {
                final filtered = _query.isEmpty
                    ? customers
                    : customers.where((c) => c.name.toLowerCase().contains(_query)).toList();
                if (customers.isEmpty) {
                  return const SingleChildScrollView(
                    child: FulusEmptyState(
                      icon: Icons.people_outline,
                      headline: 'No customers yet.',
                      body: 'Customers you sell to on credit will show up here, with a running balance.',
                    ),
                  );
                }
                if (filtered.isEmpty) {
                  return const SingleChildScrollView(
                    child: FulusEmptyState(icon: Icons.search_off, headline: 'No customers match your search.'),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const FulusListDivider(),
                  itemBuilder: (context, index) {
                    final customer = filtered[index];
                    return FulusListRow(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.selectedTintOf(context),
                        foregroundColor: AppColors.primaryOf(context),
                        child: Text(customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?'),
                      ),
                      title: Text(customer.name),
                      subtitle: Text(customer.phone ?? 'No phone number'),
                      trailing: Text(
                        formatMoney(customer.outstandingBalance, symbol: currencySymbol),
                        style: AppTypography.body.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                          fontWeight: FontWeight.w600,
                          color: customer.outstandingBalance > 0
                              ? AppColors.textPrimaryOf(context)
                              : AppColors.textSecondaryOf(context),
                        ),
                      ),
                      onTap: () => context.pushNamed(
                        'moneyCustomerProfile',
                        pathParameters: {'id': customer.localId},
                        extra: customer,
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
