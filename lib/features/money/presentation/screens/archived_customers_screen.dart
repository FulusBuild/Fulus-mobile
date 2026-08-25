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
      applyPadding: false,
      body: archivedAsync.when(
        loading: () => const FulusDelayedSkeleton(
          skeleton: Column(children: [
            FulusListRowSkeleton(),
            FulusListRowSkeleton(),
            FulusListRowSkeleton(),
          ]),
        ),
        error: (error, stack) => FulusErrorState(
          message: "Couldn't load archived customers.",
          onRetry: () => ref.invalidate(_archivedCustomersProvider),
        ),
        data: (customers) {
          if (customers.isEmpty) {
            return const FulusEmptyState(
              icon: Icons.people_outline,
              headline: 'No archived customers.',
              body: 'Anyone you archive shows up here, and can be restored any time.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            itemCount: customers.length,
            separatorBuilder: (_, __) => const FulusListDivider(),
            itemBuilder: (context, index) {
              final customer = customers[index];
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
                    color: AppColors.textSecondaryOf(context),
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
    );
  }
}

final _archivedCustomersProvider = StreamProvider<List<Customer>>((ref) {
  return ref.watch(customerRepositoryProvider).watchCustomers(archivedOnly: true);
});
