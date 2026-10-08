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
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              final inset = wide ? AppSpacing.lg : AppSpacing.sm;
              return CustomScrollView(
                slivers: [
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _CustomerSearchHeader(
                      inset: inset,
                      onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(inset, AppSpacing.sm, inset, AppSpacing.xxl),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          if (filtered.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.all(AppSpacing.lg),
                              child: Text('No customers match this view.'),
                            );
                          }
                          final customer = filtered[index];
                          return Column(
                            children: [
                              _CustomerRow(
                                customer: customer,
                                currencySymbol: currencySymbol,
                                openedFromMore: widget.openedFromMore,
                              ),
                              if (index < filtered.length - 1) const FulusListDivider(),
                            ],
                          );
                        },
                        childCount: filtered.isEmpty ? 1 : filtered.length,
                      ),
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
          if (outstanding > 0)
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                formatMoney(outstanding, symbol: currencySymbol),
                style: AppTypography.body.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontWeight: FontWeight.w700,
                  color: AppColors.warningOf(context),
                ),
              ),
            ),
          
        ],
      ),
      onTap: () => context.pushNamed(
        openedFromMore ? 'moreCustomerProfile' : 'moneyCustomerProfile',
        pathParameters: {'id': customer.localId},
        extra: customer,
      ),
    );
  }
}

class _CustomerSearchHeader extends SliverPersistentHeaderDelegate {
  const _CustomerSearchHeader({
    required this.inset,
    required this.onChanged,
  });

  final double inset;
  final ValueChanged<String> onChanged;

  @override
  double get minExtent => 56;

  @override
  double get maxExtent => 64;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.backgroundOf(context),
      padding: EdgeInsets.fromLTRB(inset, AppSpacing.sm, inset, AppSpacing.sm),
      child: FulusSearchField(
        hintText: 'Search by name or phone',
        onChanged: onChanged,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _CustomerSearchHeader oldDelegate) =>
      oldDelegate.inset != inset || oldDelegate.onChanged != onChanged;
}
