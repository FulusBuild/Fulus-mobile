import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/formatting.dart';
import '../../../../domain/entities/auth_user.dart';
import '../../../../domain/entities/return_request.dart';
import '../../../../domain/entities/sale.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../money/presentation/providers/money_providers.dart' show moneyCurrencySymbolProvider;
import '../../../stock/presentation/widgets/approval_pin_sheet.dart';

/// Voiding a sale — a cashier/owner correcting their own mistake, not a
/// customer return. Deliberately simpler than [RefundConfirmScreen]:
/// there's no line-by-line selection, because a void always claims
/// everything still eligible (ReturnRepositoryImpl.voidSale's own doc
/// comment covers why) — this screen's job is just showing what that
/// is and requiring a reason, not letting the reason and the scope
/// disagree. Same owner-approval gate for an employee-initiated void as
/// a refund gets, for the same reason: undoing a completed sale is
/// exactly as consequential either way.
class VoidSaleScreen extends ConsumerStatefulWidget {
  const VoidSaleScreen({super.key, required this.saleId});
  final String saleId;

  @override
  ConsumerState<VoidSaleScreen> createState() => _VoidSaleScreenState();
}

typedef _VoidData = ({Sale sale, List<ReturnEligibilityLine> eligibility});

class _VoidSaleScreenState extends ConsumerState<VoidSaleScreen> {
  late Future<_VoidData> _future;
  final _reasonController = TextEditingController();
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

  Future<_VoidData> _load() async {
    final sale = await ref.read(saleRepositoryProvider).getSaleByLocalId(widget.saleId);
    if (sale == null) throw StateError('Sale not found');
    final eligibility = await ref.read(returnRepositoryProvider).getReturnEligibility(widget.saleId);
    return (sale: sale, eligibility: eligibility);
  }

  @override
  Widget build(BuildContext context) {
    final currencySymbol = ref.watch(moneyCurrencySymbolProvider).value ?? '₦';

    return FulusScreen(
      title: 'Void sale',
      body: FutureBuilder<_VoidData>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return FulusErrorState(
              message: "Couldn't load this sale.",
              onRetry: () => setState(() {
                _future = _load();
              }),
            );
          }
          if (!snap.hasData) {
            return const FulusLoadingIndicator();
          }
          final data = snap.data!;
          final voidableQuantity = data.eligibility.fold<int>(0, (sum, e) => sum + e.remainingReturnable);
          if (voidableQuantity <= 0) {
            return FulusEmptyState(
              icon: Icons.block_outlined,
              headline: 'Nothing left to void on this sale.',
              body: 'It has already been fully refunded or voided.',
            );
          }

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              FulusCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'This will void the entire sale',
                      style: AppTypography.body.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimaryOf(context)),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'All ${voidableQuantity == 1 ? 'item' : 'items'} will be returned to stock'
                      '${data.sale.customerId != null ? " and any credit balance it created will be reversed" : ""}. '
                      'This cannot be undone.',
                      style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              FulusSectionHeader(title: 'Reason'),
              FulusTextField(
                label: 'Reason for voiding',
                controller: _reasonController,
                maxLines: 2,
                hintText: 'e.g. Rung up the wrong item, customer walked away',
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_bannerMessage != null) ...[
                Text(_bannerMessage!, style: AppTypography.body.copyWith(color: AppColors.errorOf(context))),
                const SizedBox(height: AppSpacing.sm),
              ],
              SizedBox(
                width: double.infinity,
                child: FulusButton(
                  label: 'Void sale — ${formatMoney(data.sale.total, symbol: currencySymbol)}',
                  variant: FulusButtonVariant.destructive,
                  loading: _submitting,
                  onPressed: _submitting ? null : () => _submit(context, data),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          );
        },
      ),
    );
  }

  Future<void> _submit(BuildContext context, _VoidData data) async {
    if (_reasonController.text.trim().isEmpty) {
      setState(() => _bannerMessage = 'Enter a reason for voiding this sale.');
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
      await ref.read(returnRepositoryProvider).voidSale(
            saleLocalId: widget.saleId,
            reason: _reasonController.text.trim(),
          );
      // See dataRefreshSignalProvider's own doc comment in
      // app/providers.dart — a void changes the numbers Home/Money/
      // Reports show, same as completing a sale does.
      ref.read(dataRefreshSignalProvider.notifier).state++;
      if (!mounted) return;
      showFulusSnackbar(context, message: 'Sale voided.');
      context.pop(); // back to the Sales transactions list
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
        _bannerMessage = "Couldn't void this sale. Please try again.";
      });
    }
  }
}
