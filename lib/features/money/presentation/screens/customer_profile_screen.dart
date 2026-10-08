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
  const CustomerProfileScreen({super.key, required this.customerId, this.preloaded, this.openedFromMore = false});

  final String customerId;
  final Customer? preloaded;
  final bool openedFromMore;

  @override
  ConsumerState<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends ConsumerState<CustomerProfileScreen> {
  late Future<Customer?> _future;
  Customer? _visibleCustomer;

  @override
  void initState() {
    super.initState();
    _visibleCustomer = widget.preloaded;
    _future = widget.preloaded != null
        ? Future.value(widget.preloaded)
        : _loadCustomer();
    _future.then((customer) {
      if (mounted && customer != null) setState(() => _visibleCustomer = customer);
    }, onError: (_) {});
  }

  Future<Customer?> _loadCustomer() => ref.read(customerRepositoryProvider).getCustomerById(widget.customerId);

  Future<void> _reload() async {
    final future = _loadCustomer();
    setState(() => _future = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    final currencySymbol = ref.watch(moneyCurrencySymbolProvider).value ?? '₦';

    return FulusScreen(
      title: 'Customer',
      body: FutureBuilder<Customer?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError && _visibleCustomer == null) {
            return FulusErrorState(message: "Couldn't load this customer.", onRetry: _reload);
          }
          if (!snapshot.hasData && _visibleCustomer == null) {
            return const _CustomerProfileLoadingSkeleton();
          }
          if (snapshot.connectionState == ConnectionState.done && !snapshot.hasData) {
            return const FulusEmptyState(icon: Icons.person_off_outlined, headline: 'This customer could not be found.');
          }
          final customer = snapshot.hasData ? snapshot.data : _visibleCustomer;
          if (customer == null) {
            return const FulusEmptyState(icon: Icons.person_off_outlined, headline: 'This customer could not be found.');
          }
          return _ProfileBody(customer: customer, currencySymbol: currencySymbol, onChanged: _reload, openedFromMore: widget.openedFromMore);
        },
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.customer, required this.currencySymbol, required this.onChanged, required this.openedFromMore});

  final Customer customer;
  final String currencySymbol;
  final VoidCallback onChanged;
  final bool openedFromMore;

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
                    Row(
                          children: [
                            FulusAvatar(name: customer.name, size: 56),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    customer.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.subheading.copyWith(
                                      color: AppColors.textPrimaryOf(context),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (customer.phone != null)
                                    Text(
                                      customer.phone!,
                                      style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                                    ),
                                  if (customer.email != null)
                                    Text(
                                      customer.email!,
                                      style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                                    ),
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
                        const SizedBox(height: AppSpacing.lg),
                        const Divider(height: 1),
                        const SizedBox(height: AppSpacing.lg),
                        LayoutBuilder(
                          builder: (context, metricConstraints) {
                            final compact = metricConstraints.maxWidth < 430;
                            final balance = _BalanceMetric(
                              label: 'Outstanding balance',
                              value: formatMoney(customer.outstandingBalance, symbol: currencySymbol),
                              prominent: true,
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
                                  const Divider(height: 1),
                                  const SizedBox(height: AppSpacing.md),
                                  limit,
                                ],
                              );
                            }
                            return Row(
                              children: [
                                Expanded(child: balance),
                                const SizedBox(width: AppSpacing.lg),
                                Container(width: 1, height: 52, color: AppColors.borderOf(context)),
                                const SizedBox(width: AppSpacing.lg),
                                Expanded(child: limit),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        FulusActionTile(
                      icon: Icons.payments_outlined,
                      label: 'Record repayment',
                      subtitle: 'Record money received from this customer.',
                      compact: true,
                          onTap: () async {
                            final result = await context.pushNamed<bool>(
                              openedFromMore ? 'moreRecordRepayment' : 'moneyRecordRepayment',
                              pathParameters: {'id': customer.localId},
                              extra: customer,
                            );
                            if (result == true) onChanged();
                          },
                        ),
                        if (customer.address != null || (customer.notes != null && customer.notes!.isNotEmpty)) ...[
                          const SizedBox(height: AppSpacing.xl),
                          const FulusSectionHeader(
                            title: 'Customer information',
                            subtitle: 'Address and notes',
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          if (customer.address != null)
                            _ProfileInfoRow(
                              icon: Icons.location_on_outlined,
                              label: 'Address',
                              value: customer.address!,
                            ),
                          if (customer.notes != null && customer.notes!.isNotEmpty) ...[
                            if (customer.address != null) const SizedBox(height: AppSpacing.lg),
                            _ProfileInfoRow(
                              icon: Icons.notes_outlined,
                              label: 'Notes',
                              value: customer.notes!,
                            ),
                          ],
                        ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const FulusSectionHeader(title: 'Purchase history', subtitle: 'Sales made to this customer'),
                    _buildPurchaseHistorySection(context, ref),
                    const SizedBox(height: AppSpacing.lg),
                    const FulusSectionHeader(title: 'Credit history', subtitle: 'Credit sales and repayments'),
                    _buildLedgerSection(ref),
                    const SizedBox(height: AppSpacing.xl),
                    _ArchiveSection(customer: customer, onChanged: onChanged),
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
          return const _InlineHistoryEmpty(
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
                    openedFromMore ? 'moreCustomerTransactionDetail' : 'moneyTransactionDetail',
                    pathParameters: openedFromMore
                        ? {'id': customer.localId, 'transactionId': transactions[i].id}
                        : {'id': transactions[i].id},
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
          return const _InlineHistoryEmpty(
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
  const _BalanceMetric({required this.label, required this.value, this.prominent = false});

  final String label;
  final String value;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondaryOf(context),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        FittedBox(
          alignment: Alignment.centerLeft,
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: (prominent ? AppTypography.display : AppTypography.subheading).copyWith(
              color: AppColors.textPrimaryOf(context),
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileInfoRow extends StatelessWidget {
  const _ProfileInfoRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.textSecondaryOf(context)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context), fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(value, style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context))),
            ],
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
      message: 'They\'ll disappear from your customer list, but their record and full credit history are kept. You can restore them from here any time — nothing here is permanent.',
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
      if (context.mounted) showFulusSnackbar(context, message: "Couldn't archive ${customer.name}. Try again.");
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
      if (context.mounted) showFulusSnackbar(context, message: "Couldn't restore ${customer.name}. Try again.");
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.center,
          child: FulusButton(
            label: _isArchived ? 'Restore this customer' : 'Archive this customer',
            variant: FulusButtonVariant.text,
            foregroundColor: _isArchived ? AppColors.primaryOf(context) : AppColors.errorOf(context),
            onPressed: () => _isArchived ? _restore(context, ref) : _archive(context, ref),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _isArchived
              ? 'Restoring brings them back to your active customer list.'
              : "They'll disappear from your customer list. Their record and credit history are kept, and this can be undone any time.",
          style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.entry, required this.currencySymbol});
  final CustomerLedgerEntry entry;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final isRepayment = entry.entryType == CustomerLedgerEntryType.repayment;
    final label = switch (entry.entryType) {
      CustomerLedgerEntryType.creditSale => 'Credit sale',
      CustomerLedgerEntryType.repayment => 'Repayment${entry.paymentMethod != null ? ' — ${entry.paymentMethod}' : ''}',
      CustomerLedgerEntryType.refundAdjustment => 'Refund adjustment',
    };
    final increasesBalance = entry.entryType == CustomerLedgerEntryType.creditSale;
    final signed = increasesBalance ? entry.amount : -entry.amount;

    return FulusListRow(
      title: Text(label),
      subtitle: Text('${formatRelativeDay(entry.createdAt)} · ${formatTime(entry.createdAt)}'),
      trailing: Text(
        formatMoney(signed, symbol: currencySymbol, showSign: true),
        style: AppTypography.body.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
          fontWeight: FontWeight.w600,
          color: isRepayment ? AppColors.primaryOf(context) : AppColors.textPrimaryOf(context),
        ),
      ),
    );
  }
}

class _PurchaseHistoryRow extends StatelessWidget {
  const _PurchaseHistoryRow({required this.transaction, required this.currencySymbol, required this.onTap});

  final MoneyTransaction transaction;
  final String currencySymbol;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final total = t.saleTotal ?? t.amount;
    final due = t.balanceDue;
    final hasSummary = t.subtitle != null && t.subtitle!.isNotEmpty;

    return FulusListRow(
      title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${formatRelativeDay(t.dateTime)} · ${formatTime(t.dateTime)}${hasSummary ? ' · ${t.subtitle}' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatMoney(total, symbol: currencySymbol),
            style: AppTypography.body.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            due > 0
                ? '${formatMoney(t.amount, symbol: currencySymbol)} paid · ${formatMoney(due, symbol: currencySymbol)} due'
                : 'Paid in full',
            style: AppTypography.caption.copyWith(
              color: due > 0 ? AppColors.errorOf(context) : AppColors.textSecondaryOf(context),
            ),
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}
class _InlineHistoryEmpty extends StatelessWidget {
  const _InlineHistoryEmpty({required this.headline, required this.body});

  final String headline;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Column(
        children: [
          Text(
            headline,
            style: AppTypography.body.copyWith(
              color: AppColors.textPrimaryOf(context),
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            body,
            style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _CustomerProfileLoadingSkeleton extends StatelessWidget {
  const _CustomerProfileLoadingSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(AppSpacing.sm),
    children: const [
      FulusListRowSkeleton(hasLeading: true),
      SizedBox(height: AppSpacing.lg),
      FulusListRowSkeleton(hasLeading: false),
      SizedBox(height: AppSpacing.md),
      FulusListRowSkeleton(hasLeading: false),
      SizedBox(height: AppSpacing.lg),
      FulusListRowSkeleton(hasLeading: false),
      FulusListRowSkeleton(hasLeading: false),
      FulusListRowSkeleton(hasLeading: false),
    ],
  );
}
