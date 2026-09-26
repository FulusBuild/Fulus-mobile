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
      backgroundColor: const Color(0xFF061B3A),
      headerBackgroundColor: const Color(0xFF061B3A),
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
  final double outstanding;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final first = customers.take(2).toList(growable: false);
    return Column(
      children: [
        Material(
          color: const Color(0xFF1473E6),
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: SizedBox(
            height: 104,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(FulusIcons.customers, color: Colors.white, size: AppIconSize.base),
                  const Spacer(),
                  Text(
                    'Total Customers  ${customers.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    'Customer credit ${formatMoney(outstanding, symbol: currencySymbol, compact: true)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            for (var i = 0; i < 2; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _CustomerCompactCard(
                  customer: i < first.length ? first[i] : null,
                  currencySymbol: currencySymbol,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _CustomerListCard extends StatelessWidget {
  const _CustomerListCard({
    required this.filtered,
    required this.currencySymbol,
  });

  final List<Customer> filtered;
  final String currencySymbol;

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

class _CustomerCompactCard extends StatelessWidget {
  const _CustomerCompactCard({required this.customer, required this.currencySymbol});
  final Customer? customer;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final name = customer?.name ?? 'No customer';
    final amount = customer == null ? '—' : formatMoney(customer!.outstandingBalance, symbol: currencySymbol, compact: true);
    return Material(
      color: const Color(0xFF0BBE6E),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: customer == null ? null : () => context.pushNamed(
          'moneyCustomerProfile',
          pathParameters: {'id': customer!.localId},
          extra: customer,
        ),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: SizedBox(height: 82, child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(FulusIcons.person, color: Colors.white, size: AppIconSize.compact),
          const Spacer(),
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
          Text(amount, style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ]),
      )),
      ),
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
