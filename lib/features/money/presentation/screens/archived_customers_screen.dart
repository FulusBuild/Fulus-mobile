import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/customer.dart';
import '../../../../shared/widgets/widgets.dart';
import '../providers/money_providers.dart';
import '../utils/money_format.dart';

/// Reached from CustomersListScreen's own actions. Exists purely so an
/// archived customer is reachable at all — the active list only ever
/// shows `deletedAt IS NULL` — and taps into the same
/// CustomerProfileScreen every active customer uses, where restoring
/// actually happens; this screen is a list, not its own action.
class ArchivedCustomersScreen extends ConsumerWidget {
  const ArchivedCustomersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currencySymbol = ref.watch(moneyCurrencySymbolProvider).value ?? '₦';
    final archivedAsync = ref.watch(_archivedCustomersProvider);

    return FulusScreen(
      title: 'Archived customers',
      subtitle: 'Customers you have moved out of the active credit book',
      body: archivedAsync.when(
        loading: () => const FulusDelayedSkeleton(
          skeleton: Column(
            children: [
              FulusSkeletonBox(height: 72),
              SizedBox(height: AppSpacing.lg),
              FulusListRowSkeleton(),
              FulusListRowSkeleton(),
              FulusListRowSkeleton(),
            ],
          ),
        ),
        error: (error, stack) => FulusErrorState(
          message: "Couldn't load archived customers.",
          reassurance: 'Your customer records are still safe — this is only about showing the archived list right now.',
          onRetry: () => ref.invalidate(_archivedCustomersProvider),
        ),
        data: (customers) {
          final outstanding = customers.fold<double>(0, (sum, customer) => sum + customer.outstandingBalance);
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              final inset = wide ? AppSpacing.lg : AppSpacing.sm;
              return ListView(
                padding: EdgeInsets.fromLTRB(inset, AppSpacing.sm, inset, AppSpacing.xxl),
                children: [
                  FulusCard(
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceAltOf(context),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Icon(Icons.archive_outlined, color: AppColors.primaryOf(context)),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${customers.length} archived ${customers.length == 1 ? 'customer' : 'customers'}',
                                style: AppTypography.subheading.copyWith(
                                  color: AppColors.textPrimaryOf(context),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                outstanding > 0
                                    ? '${formatMoney(outstanding, symbol: currencySymbol)} outstanding across this list.'
                                    : 'No outstanding customer balance in this list.',
                                style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (customers.isEmpty)
                    const FulusEmptyState(
                      icon: Icons.people_outline,
                      headline: 'No archived customers.',
                      body: 'Anyone you archive shows up here, and can be restored any time.',
                    )
                  else
                    FulusCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var index = 0; index < customers.length; index++) ...[
                            if (index > 0) const FulusListDivider(),
                            _ArchivedCustomerRow(
                              customer: customers[index],
                              currencySymbol: currencySymbol,
                            ),
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
}

class _ArchivedCustomerRow extends StatelessWidget {
  const _ArchivedCustomerRow({required this.customer, required this.currencySymbol});

  final Customer customer;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final outstanding = customer.outstandingBalance;
    return FulusListRow(
      leading: FulusAvatar(name: customer.name),
      title: Text(customer.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(customer.phone ?? 'No phone number', maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            formatMoney(outstanding, symbol: currencySymbol),
            style: AppTypography.body.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w700,
              color: outstanding > 0 ? AppColors.textPrimaryOf(context) : AppColors.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            outstanding > 0 ? 'Outstanding' : 'Settled',
            style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
          ),
        ],
      ),
      onTap: () => context.pushNamed(
        'moneyCustomerProfile',
        pathParameters: {'id': customer.localId},
        extra: customer,
      ),
    );
  }
}

final _archivedCustomersProvider = StreamProvider<List<Customer>>((ref) {
  return ref.watch(customerRepositoryProvider).watchCustomers(archivedOnly: true);
});
