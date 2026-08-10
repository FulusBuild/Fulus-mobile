import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/auth_user.dart';
import '../../../../domain/entities/product.dart';
import '../../../../domain/entities/stock_movement.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../application/stock_providers.dart';
import '../widgets/approval_pin_sheet.dart';
import '../widgets/stock_error_banner.dart';

/// Volume 6: "One entry point on Stock — '+ Record Stock' — defaults to
/// Stock In... A small switcher at the top of that same screen offers
/// Out... or Adjustment." One screen, one type switcher, matching that
/// exactly. Transfer is deliberately not one of the switcher options —
/// [StockMovementRepository]'s own doc comment confirms it has no
/// backend endpoint yet (a real Phase 2 feature, not an oversight here).
///
/// [preselectedProduct] comes from [ProductDetailScreen]'s "Record
/// stock" button (passed via go_router's `extra`, since a full [Product]
/// is more than a route param should carry) — when null (the global FAB
/// entry point on the Stock overview), this screen's first job is
/// picking which product, via the same search+list pattern the main
/// Stock screen already uses.
///
/// Stock In has no cost-price or supplier field, unlike what Volume 6's
/// prose describes ("optional cost price and supplier") — a real,
/// checked gap: [StockInDraft] only carries `productLocalId, locationId,
/// quantity, reason`, nothing else, so there's nowhere for those two
/// values to actually go if this form collected them. A product's cost
/// price is still editable — from [AddEditProductScreen], as a property
/// of the product itself, which is where this form points a user who
/// needs to change it, rather than silently dropping fields that looked
/// right on paper but don't persist anywhere.
class RecordStockMovementScreen extends ConsumerStatefulWidget {
  const RecordStockMovementScreen({super.key, this.preselectedProduct});

  final Product? preselectedProduct;

  @override
  ConsumerState<RecordStockMovementScreen> createState() => _RecordStockMovementScreenState();
}

class _RecordStockMovementScreenState extends ConsumerState<RecordStockMovementScreen> {
  Product? _product;
  StockMovementType _type = StockMovementType.stockIn;

  final _searchController = TextEditingController();
  final _quantityController = TextEditingController();
  final _noteController = TextEditingController();
  String? _outReason;
  bool _submitting = false;
  String? _bannerMessage;
  String? _quantityError;

  static const _outReasons = ['Spoiled/Damaged', 'Personal use', 'Given away', 'Other'];

  @override
  void initState() {
    super.initState();
    _product = widget.preselectedProduct;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _quantityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final quantity = int.tryParse(_quantityController.text.trim());
    if (quantity == null || quantity <= 0) {
      setState(() => _quantityError = _type == StockMovementType.adjustment
          ? 'Enter the actual count on hand.'
          : 'Enter a quantity greater than 0.');
      return;
    }
    if (_type == StockMovementType.stockOut && _outReason == null) {
      setState(() => _bannerMessage = 'Choose a reason for this stock out.');
      return;
    }

    final user = ref.read(sessionProvider);
    final needsApproval = user != null &&
        user.role == AuthRole.employee &&
        (_type == StockMovementType.stockOut || _type == StockMovementType.adjustment);
    if (needsApproval) {
      final approved = await requireOwnerApproval(context, ref);
      if (!mounted) return;
      if (!approved) return;
    }

    setState(() {
      _submitting = true;
      _bannerMessage = null;
      _quantityError = null;
    });

    try {
      final locationId = await ref.read(currentLocationIdProvider.future);
      final repo = ref.read(stockMovementRepositoryProvider);
      final product = _product!;

      switch (_type) {
        case StockMovementType.stockIn:
          await repo.recordStockIn(StockInDraft(
            productLocalId: product.localId,
            locationId: locationId,
            quantity: quantity,
            reason: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
          ));
          break;
        case StockMovementType.stockOut:
          await repo.recordStockOut(StockOutDraft(
            productLocalId: product.localId,
            locationId: locationId,
            quantity: quantity,
            reason: _outReason,
          ));
          break;
        case StockMovementType.adjustment:
          await repo.recordAdjustment(StockAdjustmentDraft(
            productLocalId: product.localId,
            locationId: locationId,
            newQuantity: quantity,
            reason: _noteController.text.trim().isEmpty ? 'Physical count' : _noteController.text.trim(),
          ));
          break;
        case StockMovementType.sale:
        case StockMovementType.transfer:
          throw StateError('Unreachable — not offered by this screen\'s type switcher.');
      }

      if (!mounted) return;
      showFulusSnackbar(context, message: 'Stock updated for ${product.name}.');
      context.pop();
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() => _bannerMessage = f.message);
    } catch (_) {
      // Same real gap as AddEditProductScreen's own save — none of
      // StockMovementRepositoryImpl's three write methods actually
      // throw Failure today, so this is the fallback that keeps a rare
      // local write error from failing silently.
      if (!mounted) return;
      setState(() => _bannerMessage = "Couldn't record this. Try again.");
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FulusScreen(
      title: 'Record stock',
      body: _product == null ? _buildProductPicker(context) : _buildForm(context),
    );
  }

  Widget _buildProductPicker(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final locationAsync = ref.watch(currentLocationIdProvider);
        return locationAsync.when(
          loading: () => const FulusLoadingIndicator(),
          error: (e, _) => FulusErrorState(message: "Couldn't load your products.", onRetry: () {}),
          data: (locationId) {
            final productsAsync = ref.watch(productsWithStockProvider(locationId));
            return productsAsync.when(
              loading: () => const FulusLoadingIndicator(),
              error: (e, _) => FulusErrorState(message: "Couldn't load your products.", onRetry: () {}),
              data: (products) {
                final query = _searchController.text.trim().toLowerCase();
                final matches = query.isEmpty
                    ? products
                    : products.where((p) => p.product.name.toLowerCase().contains(query)).toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: FulusSearchField(
                        controller: _searchController,
                        hintText: 'Which product?',
                        autofocus: true,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    Expanded(
                      child: matches.isEmpty
                          ? const FulusEmptyState(headline: 'No products match.', icon: Icons.search_off)
                          : ListView.separated(
                              itemCount: matches.length,
                              separatorBuilder: (_, __) => const FulusListDivider(),
                              itemBuilder: (context, index) {
                                final item = matches[index];
                                return FulusListRow(
                                  title: Text(item.product.name),
                                  subtitle: Text('${item.currentStock} ${item.product.unit} in stock'),
                                  onTap: () => setState(() => _product = item.product),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildForm(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (widget.preselectedProduct == null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: FulusButton(
              label: 'Change product',
              variant: FulusButtonVariant.text,
              icon: Icons.swap_horiz,
              onPressed: () => setState(() => _product = null),
            ),
          ),
        FulusCard(
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _product!.name,
                  style: AppTypography.subheading.copyWith(color: AppColors.textPrimaryOf(context)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        FulusChipRow(
          children: [
            FulusChip(
              label: 'Stock in',
              selected: _type == StockMovementType.stockIn,
              onTap: () => setState(() {
                _type = StockMovementType.stockIn;
                _quantityError = null;
              }),
            ),
            FulusChip(
              label: 'Stock out',
              selected: _type == StockMovementType.stockOut,
              onTap: () => setState(() {
                _type = StockMovementType.stockOut;
                _quantityError = null;
              }),
            ),
            FulusChip(
              label: 'Adjustment',
              selected: _type == StockMovementType.adjustment,
              onTap: () => setState(() {
                _type = StockMovementType.adjustment;
                _quantityError = null;
              }),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_bannerMessage != null) ...[
          StockErrorBanner(message: _bannerMessage!),
          const SizedBox(height: AppSpacing.lg),
        ],
        FulusTextField(
          label: _type == StockMovementType.adjustment ? 'Actual count on hand' : 'Quantity',
          controller: _quantityController,
          keyboardType: TextInputType.number,
          errorText: _quantityError,
          onChanged: (_) {
            if (_quantityError != null) setState(() => _quantityError = null);
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_type == StockMovementType.stockOut)
          FulusDropdownField<String?>(
            label: 'Reason',
            value: _outReason,
            options: [for (final r in _outReasons) FulusDropdownOption(value: r, label: r)],
            onChanged: (value) => setState(() => _outReason = value),
          )
        else
          FulusTextField(
            label: _type == StockMovementType.adjustment ? 'Reason for adjustment' : 'Note',
            controller: _noteController,
            helperText: _type == StockMovementType.stockIn
                ? 'Optional — e.g. which delivery this was.'
                : "e.g. what the physical count found.",
          ),
        const SizedBox(height: AppSpacing.xl),
        FulusButton(label: 'Save', loading: _submitting, onPressed: _submitting ? null : _submit),
      ],
    );
  }
}
