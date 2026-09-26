import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/customer.dart';
import '../../../../shared/widgets/widgets.dart';
import '../providers/money_providers.dart';
import '../utils/money_format.dart';
import '../widgets/customer_form_sheet.dart';

/// Customers live inside Money. Presentation is deliberately lightweight and
/// repository-backed so the credit book remains the source of truth.
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
    final currencySymbol = ref.watch(moneyCurrencySymbolProvider).value ?? '₦';

    return FulusScreen(
      title: 'Customers',
      subtitle: 'Your credit book and customer relationships',
      actions: [
        FulusIconButton(
          icon: Icons.person_add_alt_outlined,
          tooltip: 'Add customer',
          onPressed: () => CustomerFormSheet.show(context),
        ),
        FulusIconButton(
          icon: Icons.archive_outlined,
          tooltip: 'Archived customers',
          onPressed: () => context.pushNamed('moneyArchivedCustomers'),
        ),
      ],
      body: customersAsync.when(
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
          message: "Couldn't load your customers.",
          reassurance: 'Nothing on the credit book has been lost — this is only about showing the list right now.',
          onRetry: () => ref.invalidate(moneyCustomersProvider),
        ),
        data: (customers) {
          final filtered = _filter(customers);
          final outstanding = customers.fold<double>(0, (sum, customer) => sum + customer.outstandingBalance);
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              final inset = wide ? AppSpacing.lg : AppSpacing.sm;
              return ListView(
                padding: EdgeInsets.fromLTRB(inset, AppSpacing.sm, inset, AppSpacing.xxl),
                children: [
                  _CustomerOverview(
                    customerCount: customers.length,
                    outstanding: outstanding,
                    currencySymbol: currencySymbol,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  FulusSearchField(
                    hintText: 'Search by name or phone',
                    onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (customers.isEmpty)
                    const FulusEmptyState(
                      icon: Icons.people_outline,
                      headline: 'No customers yet',
                      body: 'Customers you sell to on credit will show up here, with a running balance.',
                    )
                  else if (filtered.isEmpty)
                    const FulusEmptyState(
                      icon: Icons.search_off,
                      headline: 'No customers match your search',
                      body: 'Try a different name or phone number.',
                    )
                  else
                    FulusCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0; i < filtered.length; i++) ...[
                            _CustomerRow(customer: filtered[i], currencySymbol: currencySymbol),
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

  List<Customer> _filter(List<Customer> customers) {
    if (_query.isEmpty) return customers;
    return customers.where((customer) {
      final name = customer.name.toLowerCase();
      final phone = (customer.phone ?? '').toLowerCase();
      return name.contains(_query) || phone.contains(_query);
    }).toList();
  }
}

class _CustomerOverview extends StatelessWidget {
  const _CustomerOverview({required this.customerCount, required this.outstanding, required this.currencySymbol});

  final int customerCount;
  final double outstanding;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    return FulusStatGrid(
      spacing: AppSpacing.sm,
      minTileWidth: 150,
      cards: [
        FulusStatCard(
          icon: Icons.people_outline,
          label: 'Customers',
          value: '$customerCount',
        ),
        FulusStatCard(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Outstanding credit',
          value: formatMoney(outstanding, symbol: currencySymbol),
          valueColor: outstanding > 0 ? AppColors.textPrimaryOf(context) : AppColors.textSecondaryOf(context),
        ),
      ],
    );
  }
}

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({required this.customer, required this.currencySymbol});

  final Customer customer;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final outstanding = customer.outstandingBalance;
    return FulusListRow(
      leading: FulusAvatar(name: customer.name),
      title: Text(customer.name),
      subtitle: Text(customer.phone ?? 'No phone number'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              formatMoney(outstanding, symbol: currencySymbol),
              style: AppTypography.body.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w700,
                color: outstanding > 0 ? AppColors.textPrimaryOf(context) : AppColors.textSecondaryOf(context),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(outstanding > 0 ? 'Outstanding' : 'Settled', style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
        ],
      ),
      onTap: () => context.pushNamed('moneyCustomerProfile', pathParameters: {'id': customer.localId}, extra: customer),
    );
  }
}
