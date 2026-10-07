import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fulus_mobile/core/money/money.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/customer.dart';
import '../../../../shared/widgets/widgets.dart';
import '../providers/money_providers.dart';
import '../utils/money_format.dart';
import '../widgets/customer_form_sheet.dart';

/// Customers live inside Money. Presentation is deliberately lightweight and
/// repository-backed so the credit book remains the source of truth.
class CustomersListScreen extends ConsumerStatefulWidget {
  const CustomersListScreen({super.key, this.openedFromMore = false});

  final bool openedFromMore;

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
      backgroundColor: const Color(0xFF061B3A),
      headerBackgroundColor: const Color(0xFF061B3A),
      actions: [
        FulusIconButton(
          icon: FulusIcons.personAdd,
          tooltip: 'Add customer',
          onPressed: () => CustomerFormSheet.show(context),
        ),
        FulusIconButton(
          icon: FulusIcons.archive,
          tooltip: 'Archived customers',
          onPressed: () => context.pushNamed(widget.openedFromMore ? 'moreArchivedCustomers' : 'moneyArchivedCustomers'),
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
          final outstanding = customers.fold<Money>(zeroMoney, (sum, customer) => sum + customer.outstandingBalance);
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              final inset = wide ? AppSpacing.lg : AppSpacing.sm;
              return ListView(
                padding: EdgeInsets.fromLTRB(inset, AppSpacing.sm, inset, AppSpacing.xxl),
                children: [
                  _CustomerOverviewHeader(
                    customers: customers,
                    outstanding: outstanding,
                    currencySymbol: currencySymbol,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FulusSearchField(
                    hintText: 'Search by name or phone',
                    onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _CustomerListCard(
                    filtered: filtered,
                    currencySymbol: currencySymbol,
                    openedFromMore: widget.openedFromMore,
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

class _CustomerOverviewHeader extends StatelessWidget {
  const _CustomerOverviewHeader({
    required this.customers,
    required this.outstanding,
    required this.currencySymbol,
  });

  final List<Customer> customers;
  final Money outstanding;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF1473E6);
    final foreground = AppColors.onColor(color);
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        height: 108,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: FulusCustomerOverviewColumn(
            icon: FulusIcons.customers,
            iconColor: foreground,
            children: [
              Text(
                'Total Customers  ${customers.length}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: foreground, fontSize: 16, fontWeight: FontWeight.w700),
              ),
              Text(
                'Customer credit ${formatMoney(outstanding, symbol: currencySymbol)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: foreground.withValues(alpha: 0.9), fontSize: 14),
              ),
            ],
          )
        ),
      ),
    );
  }
}

class _CustomerListCard extends StatelessWidget {
  const _CustomerListCard({
    required this.filtered,
    required this.currencySymbol,
    required this.openedFromMore,
  });

  final List<Customer> filtered;
  final String currencySymbol;
  final bool openedFromMore;

  @override
  Widget build(BuildContext context) {
    return FulusCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < filtered.length; i++) ...[
            _CustomerRow(
              customer: filtered[i],
              currencySymbol: currencySymbol,
              openedFromMore: openedFromMore,
            ),
            if (i < filtered.length - 1) const FulusListDivider(),
          ],
          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Text('No customers match this view.'),
            ),
        ],
      ),
    );
  }
}

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({required this.customer, required this.currencySymbol, required this.openedFromMore});

  final Customer customer;
  final String currencySymbol;
  final bool openedFromMore;

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
      onTap: () => context.pushNamed(openedFromMore ? 'moreCustomerProfile' : 'moneyCustomerProfile', pathParameters: {'id': customer.localId}, extra: customer),
    );
  }
}
