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

/// Volume 7: "a running balance... and a full ledger underneath — the
/// credit book made visible." Real data — `Customer`/
/// `CustomerLedgerEntry` via the already-implemented `CustomerRepository`
/// / `CustomerCreditRepository`.
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
    return ListView(
      children: [
        FulusCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.selectedTintOf(context),
                    foregroundColor: AppColors.primaryOf(context),
                    child: Text(customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?'),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customer.name,
                          style: AppTypography.subheading.copyWith(color: AppColors.textPrimaryOf(context)),
                        ),
                        if (customer.phone != null)
                          Text(customer.phone!, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
                        // Feature (customer management): "Basic
                        // information... Address. Other existing
                        // customer information" — email/address were
                        // captured (Customer already has both fields)
                        // but never actually shown anywhere on this
                        // screen.
                        if (customer.email != null)
                          Text(customer.email!, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
                        if (customer.address != null)
                          Text(customer.address!, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
                        // Feature (customer management gap-closure):
                        // same "captured but never shown" gap as email/
                        // address above — Customer.notes has carried a
                        // free-text note since Customer was first
                        // modeled, now genuinely settable too (see
                        // CustomerFormSheet's Notes field).
                        if (customer.notes != null && customer.notes!.isNotEmpty)
                          Text(customer.notes!, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
                      ],
                    ),
                  ),
                  // Feature (customer management): "no proper way to
                  // edit existing customer information" — this is that
                  // way.
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Outstanding balance', style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context))),
                  // Responsive UI audit — Flexible+ellipsis added, same
                  // reasoning as supplier_profile_screen's identical row:
                  // the label is fixed, the balance isn't bounded.
                  Flexible(
                    child: Text(
                      formatMoney(customer.outstandingBalance, symbol: currencySymbol),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: AppTypography.heading.copyWith(
                        color: AppColors.textPrimaryOf(context),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
              if (customer.creditLimit != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Credit limit: ${formatMoney(customer.creditLimit!, symbol: currencySymbol)} — a guide, not a hard block',
                  style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                ),
              ],
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
        FulusSectionHeader(title: 'Purchase history'),
        _buildPurchaseHistorySection(context, ref),
        const SizedBox(height: AppSpacing.lg),
        FulusSectionHeader(title: 'Credit history'),
        _buildLedgerSection(ref),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }

  /// Feature (customer profile gap-closure): every past sale rung up
  /// for this customer, most recent first — the "past transactions...
  /// tappable through to transaction_detail_screen.dart" half of the
  /// profile's history, distinct from the credit-only ledger below.
  /// One-shot [FutureProvider], not the ledger's `StreamProvider` — see
  /// [moneyCustomerPurchaseHistoryProvider]'s own doc comment for why.
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
                  // Same navigation call money_screen.dart's own
                  // history list already uses — transaction_detail_
                  // screen.dart accepts this exact preloaded
                  // MoneyTransaction via `extra` and doesn't need a
                  // re-fetch to render it.
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

/// Feature (customer profile gap-closure): a Purchase History row —
/// date, receipt number, item summary, total, payment status, amount
/// paid, and outstanding amount, per the original request. Total and
/// status share the trailing slot the same way transaction_detail_
/// screen.dart collapses "Balance due" and "Status: Paid in full" into
/// one context-dependent line rather than always printing all four
/// numbers, since for the common fully-paid sale that would just repeat
/// the total twice for no reason.
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
