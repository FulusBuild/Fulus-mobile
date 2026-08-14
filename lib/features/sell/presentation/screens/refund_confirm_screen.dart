import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/auth_user.dart';
import '../../../../domain/entities/return_request.dart';
import '../../../../domain/entities/sale.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../money/presentation/providers/money_providers.dart' show moneyCurrencySymbolProvider;
import '../../../stock/presentation/widgets/approval_pin_sheet.dart';

const _refundMethods = [
  (key: 'cash', label: 'Cash'),
  (key: 'mobile_money', label: 'Mobile Money'),
  (key: 'card', label: 'Card'),
  (key: 'credit', label: 'Account credit'),
];

/// Volume 5's Refund Confirm — select which lines and how much of each
/// to return, against real eligibility (a line already partially
/// returned can't be over-returned), then commit. Employee-initiated
/// refunds reuse [requireOwnerApproval] — the same PIN mechanism Stock
/// Out/Adjustment already uses — per Volume 5: "an employee-initiated
/// refund requires the same owner approval."
class RefundConfirmScreen extends ConsumerStatefulWidget {
  const RefundConfirmScreen({super.key, required this.saleId});
  final String saleId;

  @override
  ConsumerState<RefundConfirmScreen> createState() => _RefundConfirmScreenState();
}

typedef _ConfirmData = ({Sale sale, List<ReturnEligibilityLine> eligibility});

class _RefundConfirmScreenState extends ConsumerState<RefundConfirmScreen> {
  late Future<_ConfirmData> _future;
  final _reasonController = TextEditingController();
  final Map<String, int> _selectedQuantities = {}; // productLocalId -> qty
  String _refundMethod = 'cash';
  bool _submitting = false;
  String? _bannerMessage;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<_ConfirmData> _load() async {
    final sale = await ref.read(saleRepositoryProvider).getSaleByLocalId(widget.saleId);
    if (sale == null) throw StateError('Sale not found');
    final eligibility = await ref.read(returnRepositoryProvider).getReturnEligibility(widget.saleId);
    if (sale.paymentMethod != null && _refundMethods.any((m) => m.key == sale.paymentMethod)) {
      _refundMethod = sale.paymentMethod!;
    }
    return (sale: sale, eligibility: eligibility);
  }

  int get _totalSelectedQuantity => _selectedQuantities.values.fold(0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    final currencySymbol = ref.watch(moneyCurrencySymbolProvider).valueOrNull ?? '₦';

    return FulusScreen(
      title: 'Confirm refund',
      body: FutureBuilder<_ConfirmData>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return FulusErrorState(
              message: "Couldn't load this sale.",
              onRetry: () => setState(() => _future = _load()),
            );
          }
          if (!snap.hasData) {
            return const FulusLoadingIndicator();
          }
          final data = snap.data!;
          final eligibleLines = data.eligibility.where((e) => e.remainingReturnable > 0).toList();

          return ListView(
            children: [
              FulusSectionHeader(title: 'Items'),
              if (eligibleLines.isEmpty)
                FulusEmptyState(
                  icon: Icons.assignment_return_outlined,
                  headline: 'Nothing left to return on this sale.',
                  body: 'Every item has already been fully refunded.',
                )
              else
                for (final line in eligibleLines) _EligibilityRow(
                  line: line,
                  sale: data.sale,
                  selected: _selectedQuantities[line.productLocalId] ?? 0,
                  onChanged: (qty) => setState(() {
                    if (qty <= 0) {
                      _selectedQuantities.remove(line.productLocalId);
                    } else {
                      _selectedQuantities[line.productLocalId] = qty;
                    }
                  }),
                ),
              if (eligibleLines.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                FulusSectionHeader(title: 'Refund method'),
                FulusDropdownField<String>(
                  label: 'Refund method',
                  value: _refundMethod,
                  options: [for (final m in _refundMethods) FulusDropdownOption(value: m.key, label: m.label)],
                  onChanged: (value) => setState(() => _refundMethod = value),
                ),
                const SizedBox(height: AppSpacing.lg),
                FulusSectionHeader(title: 'Reason'),
                FulusTextField(
                  label: 'Reason for return',
                  controller: _reasonController,
                  maxLines: 2,
                  hintText: 'e.g. Wrong size, customer changed mind',
                ),
                const SizedBox(height: AppSpacing.lg),
                if (_bannerMessage != null) ...[
                  Text(_bannerMessage!, style: AppTypography.body.copyWith(color: AppColors.errorOf(context))),
                  const SizedBox(height: AppSpacing.sm),
                ],
                SizedBox(
                  width: double.infinity,
                  child: FulusButton(
                    label: 'Confirm refund${_totalSelectedQuantity > 0 ? ' — $currencySymbol${_estimatedRefund(data).toStringAsFixed(2)}' : ''}',
                    loading: _submitting,
                    onPressed: _submitting ? null : () => _submit(context, data),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Estimate only, for the button label — real pricing happens in
  /// ReturnRepository.createReturn via a weighted average across every
  /// line for that product (return_repository_impl.dart's own
  /// `_weightedAveragePrice`), for the edge case where the same product
  /// appears as more than one line in a sale. For the common case (one
  /// line per product) that average is just `unitPrice`, which is all
  /// SaleItem actually carries forward from the sale — no per-line
  /// discount field survives onto the persisted Sale/SaleItem the way
  /// it does on an in-progress CartItem, so there's nothing to subtract
  /// here even for an item that was discounted at sale time.
  double _estimatedRefund(_ConfirmData data) {
    double total = 0;
    for (final item in data.sale.items) {
      final qty = _selectedQuantities[item.productLocalId];
      if (qty == null || qty <= 0) continue;
      total += item.unitPrice * qty;
    }
    return total;
  }

  Future<void> _submit(BuildContext context, _ConfirmData data) async {
    if (_selectedQuantities.isEmpty) {
      setState(() => _bannerMessage = 'Select at least one item to return.');
      return;
    }
    if (_reasonController.text.trim().isEmpty) {
      setState(() => _bannerMessage = 'Enter a reason for this return.');
      return;
    }

    final user = ref.read(sessionProvider);
    final isEmployee = user?.role == AuthRole.employee;
    if (isEmployee) {
      final approved = await requireOwnerApproval(context, ref);
      if (!mounted) return;
      if (!approved) return;
    }

    setState(() {
      _submitting = true;
      _bannerMessage = null;
    });
    try {
      final returnRepo = ref.read(returnRepositoryProvider);
      final created = await returnRepo.createReturn(
        originalSaleLocalId: widget.saleId,
        items: [
          for (final entry in _selectedQuantities.entries)
            ReturnItemRequest(productLocalId: entry.key, quantity: entry.value),
        ],
        returnReason: _reasonController.text.trim(),
        refundMethod: _refundMethod,
        // Owner acting directly, or an employee whose PIN was just
        // verified above — both cases are "approved right now," so
        // this creates already-approved rather than leaving a pending
        // return with no review screen to act on it yet (Approval Push
        // — a later, separate piece of work; see the audit's
        // Nice-to-have list).
        autoApprove: true,
      );
      // createReturn only ever creates as approved or pending — never
      // completed — so stock/credit are restored by this second call,
      // which mirrors what completing a Daily Closing does elsewhere in
      // this app: one user action, two repository calls, because the
      // domain layer keeps "approved" and "actually executed" separate
      // on purpose (a return can be approved and then still fail to
      // complete, e.g. a data conflict) rather than because this screen
      // has two steps for the cashier.
      await returnRepo.completeReturn(created.localId);

      if (!mounted) return;
      showFulusSnackbar(context, message: 'Refund completed.');
      context.pop();
      context.pop(); // back through Refund Search to wherever refunds were opened from
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _bannerMessage = f.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _bannerMessage = "Couldn't complete this refund. Please try again.";
      });
    }
  }
}

class _EligibilityRow extends StatelessWidget {
  const _EligibilityRow({required this.line, required this.sale, required this.selected, required this.onChanged});
  final ReturnEligibilityLine line;
  final Sale sale;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final item = sale.items.firstWhere(
      (i) => i.productLocalId == line.productLocalId,
      orElse: () => sale.items.first,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: FulusCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.description.isNotEmpty ? item.description : 'Item',
                    style: AppTypography.body.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimaryOf(context)),
                  ),
                  Text(
                    '${line.remainingReturnable} of ${line.purchasedQuantity} returnable',
                    style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: selected > 0 ? () => onChanged(selected - 1) : null,
            ),
            Text('$selected', style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context))),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: selected < line.remainingReturnable ? () => onChanged(selected + 1) : null,
            ),
          ],
        ),
      ),
    );
  }
}
