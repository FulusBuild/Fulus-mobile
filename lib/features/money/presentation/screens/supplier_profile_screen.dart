import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/supplier.dart';
import '../../../../domain/entities/supplier_ledger_entry.dart';
import '../../../../shared/widgets/widgets.dart';
import '../providers/money_providers.dart';
import '../utils/money_format.dart';
import '../widgets/supplier_form_sheet.dart';

/// Supplier profile remains repository-backed and reactive. This pass only
/// refines its workspace presentation and responsive layout.
class SupplierProfileScreen extends ConsumerStatefulWidget {
  const SupplierProfileScreen({super.key, required this.supplierId, this.preloaded});

  final String supplierId;
  final Supplier? preloaded;

  @override
  ConsumerState<SupplierProfileScreen> createState() => _SupplierProfileScreenState();
}

class _SupplierProfileScreenState extends ConsumerState<SupplierProfileScreen> {
  late Future<Supplier?> _future;
  Supplier? _visibleSupplier;

  @override
  void initState() {
    super.initState();
    _visibleSupplier = widget.preloaded;
    _future = widget.preloaded != null
        ? Future.value(widget.preloaded)
        : _loadSupplier();
    _future.then((supplier) {
      if (mounted && supplier != null) setState(() => _visibleSupplier = supplier);
    }, onError: (_) {});
  }

  Future<Supplier?> _loadSupplier() => ref.read(supplierRepositoryProvider).getSupplierById(widget.supplierId);

  Future<void> _reload() async {
    final future = _loadSupplier();
    setState(() => _future = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    final currencySymbol = ref.watch(moneyCurrencySymbolProvider).value ?? '₦';

    return FulusScreen(
      title: 'Supplier',
      body: FutureBuilder<Supplier?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError && _visibleSupplier == null) {
            return FulusErrorState(message: "Couldn't load this supplier.", onRetry: _reload);
          }
          if (!snapshot.hasData && _visibleSupplier == null) {
            return const _SupplierProfileLoadingSkeleton();
          }
          if (snapshot.connectionState == ConnectionState.done && !snapshot.hasData) {
            return const FulusEmptyState(icon: Icons.local_shipping_outlined, headline: 'This supplier could not be found.');
          }
          final supplier = snapshot.hasData ? snapshot.data : _visibleSupplier;
          if (supplier == null) {
            return const FulusEmptyState(icon: Icons.local_shipping_outlined, headline: 'This supplier could not be found.');
          }
          return _SupplierProfileBody(supplier: supplier, currencySymbol: currencySymbol, onChanged: _reload);
        },
      ),
    );
  }
}

class _SupplierProfileBody extends ConsumerWidget {
  const _SupplierProfileBody({required this.supplier, required this.currencySymbol, required this.onChanged});

  final Supplier supplier;
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
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.selectedTintOf(context),
                                ),
                                child: Icon(Icons.local_shipping_outlined, color: AppColors.primaryOf(context)),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      supplier.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTypography.subheading.copyWith(color: AppColors.textPrimaryOf(context)),
                                    ),
                                    if (supplier.phone != null)
                                      Text(supplier.phone!, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
                                    if (supplier.email != null)
                                      Text(supplier.email!, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
                                  ],
                                ),
                              ),
                              FulusIconButton(
                                icon: Icons.edit_outlined,
                                tooltip: 'Edit supplier',
                                onPressed: () async {
                                  final saved = await SupplierFormSheet.show(context, existing: supplier);
                                  if (saved != null) onChanged();
                                },
                              ),
                            ],
                          ),
                          if (supplier.address != null) ...[
                            const SizedBox(height: AppSpacing.md),
                            FulusListRow(
                              leading: const Icon(Icons.location_on_outlined),
                              title: const Text('Address'),
                              subtitle: Text(supplier.address!),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.lg),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                            child: LayoutBuilder(
                              builder: (context, metricConstraints) {
                                final compact = metricConstraints.maxWidth < 430;
                                final balance = _BalanceMetric(
                                  label: 'Outstanding balance',
                                  value: formatMoney(supplier.outstandingBalance, symbol: currencySymbol),
                                );
                                final status = _BalanceMetric(
                                  label: 'Account status',
                                  value: supplier.deletedAt == null ? 'Active' : 'Archived',
                                );
                                if (compact) {
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      balance,
                                      const SizedBox(height: AppSpacing.md),
                                      status,
                                    ],
                                  );
                                }
                                return Row(
                                  children: [
                                    Expanded(child: balance),
                                    const SizedBox(width: AppSpacing.lg),
                                    Container(width: 1, height: 44, color: AppColors.borderOf(context)),
                                    const SizedBox(width: AppSpacing.lg),
                                    Expanded(child: status),
                                  ],
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          FulusActionTile(
                            icon: Icons.payments_outlined,
                            label: 'Pay supplier',
                            subtitle: 'Record a payment against this balance.',
                            onTap: () async {
                              final result = await context.pushNamed<bool>(
                                'moneyPaySupplier',
                                pathParameters: {'id': supplier.localId},
                                extra: supplier,
                              );
                              if (result == true) onChanged();
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    const FulusSectionHeader(
                      title: 'Payment history',
                      subtitle: 'Stock bought on credit and payments made',
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

  Widget _buildLedgerSection(WidgetRef ref) {
    final ledgerAsync = ref.watch(moneySupplierLedgerProvider(supplier.localId));
    return ledgerAsync.when(
      loading: () => Column(children: List.generate(3, (_) => const FulusListRowSkeleton(hasLeading: false))),
      error: (error, stack) => FulusErrorState(
        message: "Couldn't load this supplier's history.",
        onRetry: () => ref.invalidate(moneySupplierLedgerProvider(supplier.localId)),
      ),
      data: (entries) {
        if (entries.isEmpty) {
          return const FulusEmptyState(
            icon: Icons.receipt_long_outlined,
            headline: 'No payment history yet.',
            body: 'Stock bought on credit and payments made will show up here.',
          );
        }
        return Column(
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0) const FulusListDivider(indented: false),
                _SupplierLedgerRow(entry: entries[i], currencySymbol: currencySymbol),
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

class _SupplierLedgerRow extends StatelessWidget {
  const _SupplierLedgerRow({required this.entry, required this.currencySymbol});
  final SupplierLedgerEntry entry;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final isPayment = entry.entryType == SupplierLedgerEntryType.paymentMade;
    final label = switch (entry.entryType) {
      SupplierLedgerEntryType.stockPurchaseOnCredit => 'Stock bought on credit',
      SupplierLedgerEntryType.paymentMade => 'Payment${entry.paymentMethod != null ? ' — ${entry.paymentMethod}' : ''}',
    };
    final signed = isPayment ? -entry.amount : entry.amount;

    return FulusListRow(
      title: Text(label),
      subtitle: Text('${formatRelativeDay(entry.createdAt)} · ${formatTime(entry.createdAt)}'),
      trailing: Text(
        formatMoney(signed, symbol: currencySymbol, showSign: true),
        style: AppTypography.body.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimaryOf(context),
        ),
      ),
    );
  }
}
class _SupplierProfileLoadingSkeleton extends StatelessWidget {
  const _SupplierProfileLoadingSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(AppSpacing.sm),
    children: const [
      FulusCardSkeleton(),
      SizedBox(height: AppSpacing.lg),
      FulusCardSkeleton(),
      SizedBox(height: AppSpacing.lg),
      FulusListRowSkeleton(hasLeading: false),
      FulusListRowSkeleton(hasLeading: false),
      FulusListRowSkeleton(hasLeading: false),
    ],
  );
}
