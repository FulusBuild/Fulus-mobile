import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/customer.dart';
import '../../../../domain/entities/customer_ledger_entry.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../domain/money_transaction.dart';
import '../providers/money_providers.dart';
import '../utils/money_format.dart';
import '../widgets/customer_form_sheet.dart';

/// Customer profile remains repository-backed and reactive. This pass only
/// refines its workspace presentation and responsive layout.
class CustomerProfileScreen extends ConsumerStatefulWidget {
  const CustomerProfileScreen({super.key, required this.customerId, this.preloaded});

  final String customerId;
  final Customer? preloaded;

  @override
  ConsumerState<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends ConsumerState<CustomerProfileScreen> {
  late Future<Customer?> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.preloaded != null
        ? Future.value(widget.preloaded)
        : ref.read(customerRepositoryProvider).getCustomerById(widget.customerId);
  }

  Future<void> _reload() async {
    setState(() {
      _future = ref.read(customerRepositoryProvider).getCustomerById(widget.customerId);
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final currencySymbol = ref.watch(moneyCurrencySymbolProvider).value ?? '₦';

    return FulusScreen(
      title: 'Customer',
      subtitle: 'Customer details, purchases and credit history',
      body: FutureBuilder<Customer?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return FulusErrorState(message: "Couldn't load this customer.", onRetry: _reload);
          }
          if (!snapshot.hasData) {
            return const Center(child: FulusLoadingIndicator());
          }
          final customer = snapshot.data;
          if (customer == null) {
            return const FulusEmptyState(icon: Icons.person_off_outlined, headline: 'This customer could not be found.');
          }
          return _ProfileBody(customer: customer, currencySymbol: currencySymbol, onChanged: _reload);
        },
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.customer, required this.currencySymbol, required this.onChanged});

  final Customer customer;
  final String currencySymbol;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        final inset = wide ? AppSpacing.lg : AppSpacing.sm;
        return ListView(
          padding: EdgeInsets.fromLTRB(inset, AppSpacing.sm, inset, AppSpacing.xxl),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FulusCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              FulusAvatar(name: customer.name, size: 52),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      customer.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTypography.subheading.copyWith(color: AppColors.textPrimaryOf(context)),
                                    ),
                                    if (customer.phone != null)
                                      Text(customer.phone!, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
                                    if (customer.email != null)
                                      Text(customer.email!, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
                                  ],
                                ),
                              ),
                              FulusIconButton(
                                icon: Icons.edit_outlined,
                                tooltip: 'Edit customer',
                                onPressed: () async {
                                  final saved = await CustomerFormSheet.show(context, existing: customer);
                                  if (saved != null) onChanged();
                                },
                              ),
                            ],
                          ),
                          if (customer.address != null || (customer.notes != null && customer.notes!.isNotEmpty)) ...[
                            const SizedBox(height: AppSpacing.md),
                            if (customer.address != null)
                              FulusListRow(
                                leading: const Icon(Icons.location_on_outlined),
                                title: const Text('Address'),
                                subtitle: Text(customer.address!),
                              ),
                            if (customer.notes != null && customer.notes!.isNotEmpty)
                              FulusListRow(
                                leading: const Icon(Icons.notes_outlined),
                                title: const Text('Notes'),
                                subtitle: Text(customer.notes!),
                              ),
                          ],
                          const SizedBox(height: AppSpacing.lg),
                          FulusCard(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: LayoutBuilder(
                              builder: (context, metricConstraints) {
                                final compact = metricConstraints.maxWidth < 430;
                                final balance = _BalanceMetric(
                                  label: 'Outstanding balance',
                                  value: formatMoney(customer.outstandingBalance, symbol: currencySymbol),
                                );
                                final limit = customer.creditLimit == null
                                    ? const _BalanceMetric(label: 'Credit limit', value: 'Not set')
                                    : _BalanceMetric(
                                        label: 'Credit limit',
                                        value: formatMoney(customer.creditLimit!, symbol: currencySymbol),
                                      );
                                if (compact) {
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      balance,
                                      const SizedBox(height: AppSpacing.md),
                                      limit,
                                    ],
                                  );
                                }
                                return Row(
                                  children: [
                                    Expanded(child: balance),
                                    const SizedBox(width: AppSpacing.lg),
                                    Container(width: 1, height: 44, color: AppColors.borderOf(context)),
                                    const SizedBox(width: AppSpacing.lg),
                                    Expanded(child: limit),
                                  ],
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          SizedBox(
                            width: double.infinity,
                            child: FulusButton(
                              label: 'Record repayment',
                              onPressed: () async {
                                final result = await context.pushNamed<bool>(
                                  'moneyRecordRepayment',
                                  pathParameters: {'id': customer.localId},
                                  extra: customer,
                                );
                                if (result == true) onChanged();
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _ArchiveSection(customer: customer, onChanged: onChanged),
                    const SizedBox(height: AppSpacing.lg),
                    const FulusSectionHeader(
                      title: 'Purchase history',
                      subtitle: 'Sales made to this customer',
                    ),
                    _buildPurchaseHistorySection(context, ref),
                    const SizedBox(height: AppSpacing.lg),
                    const FulusSectionHeader(
                      title: 'Credit history',
                      subtitle: 'Credit sales and repayments',
                    ),
                    _buildLedgerSection(ref),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPurchaseHistorySection(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(moneyCustomerPurchaseHistoryProvider(customer.localId));
    return historyAsync.when(
      loading: () => Column(children: List.generate(3, (_) => const FulusListRowSkeleton(hasLeading: false))),
      error: (error, stack) => FulusErrorState(
        message: "Couldn't load this customer's purchase history.",
        onRetry: () => ref.invalidate(moneyCustomerPurchaseHistoryProvider(customer.localId)),
      ),
      data: (transactions) {
        if (transactions.isEmpty) {
          return const FulusEmptyState(
            icon: Icons.point_of_sale_outlined,
            headline: 'No purchases yet.',
            body: 'Sales made to this customer will show up here.',
          );
        }
        return FulusCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < transactions.length; i++) ...[
                if (i > 0) const FulusListDivider(indented: false),
                _PurchaseHistoryRow(
                  transaction: transactions[i],
                  currencySymbol: currencySymbol,
                  onTap: () => context.pushNamed(
                    'moneyTransactionDetail',
                    pathParameters: {'id': transactions[i].id},
                    extra: transactions[i],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildLedgerSection(WidgetRef ref) {
    final ledgerAsync = ref.watch(moneyCustomerLedgerProvider(customer.localId));
    return ledgerAsync.when(
      loading: () => Column(children: List.generate(3, (_) => const FulusListRowSkeleton(hasLeading: false))),
      error: (error, stack) => FulusErrorState(
        message: "Couldn't load this customer's history.",
        onRetry: () => ref.invalidate(moneyCustomerLedgerProvider(customer.localId)),
      ),
      data: (entries) {
        if (entries.isEmpty) {
          return const FulusEmptyState(
            icon: Icons.receipt_long_outlined,
            headline: 'No credit history yet.',
            body: 'Credit sales and repayments for this customer will show up here.',
          );
        }
        return FulusCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0) const FulusListDivider(indented: false),
                _LedgerRow(entry: entries[i], currencySymbol: currencySymbol),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _BalanceMetric extends StatelessWidget {
  const _BalanceMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
        const SizedBox(height: 2),
        FittedBox(
          alignment: Alignment.centerLeft,
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: AppTypography.subheading.copyWith(color: AppColors.textPrimaryOf(context), fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _ArchiveSection extends ConsumerWidget {
  const _ArchiveSection({required this.customer, required this.onChanged});

  final Customer customer;
  final VoidCallback onChanged;

  bool get _isArchived => customer.deletedAt != null;

  Future<void> _archive(BuildContext context, WidgetRef ref) async {
    final confirmed = await showFulusConfirmDialog(
      context,
      title: 'Archive ${customer.name}?',
      message: 'They\'ll disappear from your customer list, but their record and full '
          "credit history are kept. You can restore them from here any time — nothing "
          'here is permanent.',
      confirmLabel: 'Archive',
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(customerRepositoryProvider).archiveCustomer(customer.localId);
      if (context.mounted) {
        showFulusSnackbar(context, message: '${customer.name} was archived.');
        onChanged();
      }
    } catch (_) {
      if (context.mounted) {
        showFulusSnackbar(context, message: "Couldn't archive ${customer.name}. Try again.");
      }
    }
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(customerRepositoryProvider).restoreCustomer(customer.localId);
      if (context.mounted) {
        showFulusSnackbar(context, message: '${customer.name} was restored.');
        onChanged();
      }
    } catch (_) {
      if (context.mounted) {
        showFulusSnackbar(context, message: "Couldn't restore ${customer.name}. Try again.");
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FulusButton(
          label: _isArchived ? 'Restore this customer' : 'Archive this customer',
          variant: _isArchived ? FulusButtonVariant.secondary : FulusButtonVariant.destructive,
          onPressed: () => _isArchived ? _restore(context, ref) : _archive(context, ref),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _isArchived
              ? 'Restoring brings them back to your active customer list.'
              : "They'll disappear from your customer list. Their record and credit "
                  'history are kept, and this can be undone any time.',
          style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
