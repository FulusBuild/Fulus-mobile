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

/// Volume 8, Decision 26's supplier mirror of `customer_profile_screen
/// .dart` — real data via `SupplierRepository`/`SupplierCreditRepository`.
class SupplierProfileScreen extends ConsumerStatefulWidget {
  const SupplierProfileScreen({super.key, required this.supplierId, this.preloaded});

  final String supplierId;
  final Supplier? preloaded;

  @override
  ConsumerState<SupplierProfileScreen> createState() => _SupplierProfileScreenState();
}

class _SupplierProfileScreenState extends ConsumerState<SupplierProfileScreen> {
  late Future<Supplier?> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.preloaded != null
        ? Future.value(widget.preloaded)
        : ref.read(supplierRepositoryProvider).getSupplierById(widget.supplierId);
  }

  Future<void> _reload() async {
    setState(() {
      _future = ref.read(supplierRepositoryProvider).getSupplierById(widget.supplierId);
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final currencySymbol = ref.watch(moneyCurrencySymbolProvider).valueOrNull ?? '₦';

    return FulusScreen(
      title: 'Supplier',
      body: FutureBuilder<Supplier?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return FulusErrorState(message: "Couldn't load this supplier.", onRetry: _reload);
          }
          if (!snapshot.hasData) {
            return const Center(child: FulusLoadingIndicator());
          }
          final supplier = snapshot.data;
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
    return ListView(
      children: [
        FulusCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.surfaceAltOf(context)),
                    child: Icon(Icons.local_shipping_outlined, color: AppColors.textSecondaryOf(context)),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(supplier.name, style: AppTypography.subheading.copyWith(color: AppColors.textPrimaryOf(context))),
                        if (supplier.phone != null)
                          Text(supplier.phone!, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('You owe', style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context))),
                  Text(
                    formatMoney(supplier.outstandingBalance, symbol: currencySymbol),
                    style: AppTypography.heading.copyWith(
                      color: AppColors.textPrimaryOf(context),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FulusButton(
                  label: 'Pay supplier',
                  onPressed: () async {
                    final result = await context.pushNamed<bool>(
                      'moneyPaySupplier',
                      pathParameters: {'id': supplier.localId},
                      extra: supplier,
                    );
                    if (result == true) onChanged();
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        FulusSectionHeader(title: 'Payment history'),
        _buildLedgerSection(ref),
        const SizedBox(height: AppSpacing.xl),
      ],
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
        return FulusCard(
          padding: EdgeInsets.zero,
          child: Column(
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
