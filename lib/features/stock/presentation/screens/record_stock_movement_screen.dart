import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/auth_user.dart';
import '../../../../domain/entities/permission.dart';
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
/// Stock In's cost-price and supplier fields (Volume 6's prose:
/// "optional cost price and supplier") update the [Product] itself via
/// [ProductRepository.updateProduct] — not new [StockMovement] columns.
/// [StockInDraft] and the real backend `StockInRequest` genuinely have
/// no room for either (verified against the actual wire schema), so
/// this deliberately doesn't invent fields that would silently fail to
/// sync; it reuses the one place cost price and supplier already
/// persist for real. Picking a supplier surfaces a "Paid now" / "On
/// account" choice — on account calls
/// [SupplierCreditRepository.recordStockPurchaseOnCredit], the same
/// forward seam a credit sale calls on the customer side, using
/// cost price × quantity as the amount owed.
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
  final _costPriceController = TextEditingController();
  String? _outReason;
  bool _submitting = false;
  String? _bannerMessage;
  String? _quantityError;

  /// Stock In's optional "bought on credit" fields — only ever read in
  /// the [StockMovementType.stockIn] branch of [_submit].
  String? _supplierId;
  bool _onAccount = false;
  String? _creditError;

  static const _outReasons = ['Spoiled/Damaged', 'Personal use', 'Given away', 'Other'];

  @override
  void initState() {
    super.initState();
    _product = widget.preselectedProduct;
    if (_product != null) _seedFromProduct(_product!);
  }

  /// Cost price/supplier default to whatever's already on the product —
  /// leaving them untouched on submit is then a genuine no-op, not a
  /// silent reset (see [_recordCostAndCredit]).
  void _seedFromProduct(Product product) {
    _costPriceController.text = product.costPrice == 0 ? '' : product.costPrice.toStringAsFixed(2);
    _supplierId = product.supplierId;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _quantityController.dispose();
    _noteController.dispose();
    _costPriceController.dispose();
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
    if (_type == StockMovementType.stockIn && _supplierId != null && _onAccount) {
      final cost = double.tryParse(_costPriceController.text.trim());
      if (cost == null || cost <= 0) {
        setState(() => _creditError = 'Enter a cost price so we know how much is owed.');
        return;
      }
    }

    final user = ref.read(sessionProvider);
    final requiresApprovalForType =
        _type == StockMovementType.stockOut || _type == StockMovementType.adjustment;
    final needsApproval = user != null &&
        user.role != AuthRole.owner &&
        requiresApprovalForType &&
        !(await ref.read(permissionRepositoryProvider).hasPermission(
              userId: user.id,
              role: user.role,
              permission: Permission.approveWithoutSupervisor,
            ));
    if (!mounted) return;
    if (needsApproval) {
      final approved = await requireOwnerApproval(context, ref);
      if (!mounted) return;
      if (!approved) return;
    }

    setState(() {
      _submitting = true;
      _bannerMessage = null;
      _quantityError = null;
      _creditError = null;
    });

    try {
      final locationId = await ref.read(currentLocationIdProvider.future);
      final repo = ref.read(stockMovementRepositoryProvider);
      final product = _product!;

      switch (_type) {
        case StockMovementType.stockIn:
          final movement = await repo.recordStockIn(StockInDraft(
            productLocalId: product.localId,
            locationId: locationId,
            quantity: quantity,
            reason: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
          ));
          await _recordCostAndCredit(product: product, quantity: quantity, movement: movement);
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

      // See dataRefreshSignalProvider's own doc comment in
      // app/providers.dart — Reports' Inventory figures and Home read
      // this the same one-shot-Future way Money does, so they need the
      // same nudge (Stock's own screen already updates live via a
      // Drift stream and doesn't need this).
      ref.read(dataRefreshSignalProvider.notifier).state++;

      if (!mounted) return;
      // Bug fix (business-logic audit): this used to say "Stock
      // updated" — but stock-in/out/adjustment currentStock is only
      // written once the sync task reaches the server and gets a
      // response back (see StockMovementSyncHandler; confirmed by
      // grep — unlike a sale's stock decrement, which does write
      // locally right away, nothing here does). On a slow or offline
      // connection, that gap could be long, and this message claimed
      // it was already closed. "Recorded" is accurate either way —
      // the movement itself is safely queued the instant this returns,
      // regardless of when the number on the Stock screen catches up.
      showFulusSnackbar(context, message: 'Stock movement recorded for ${product.name}.');
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

  /// Cost price and supplier are [Product] fields, not [StockMovement]
  /// ones (see this class's own doc comment) — so this writes to the
  /// product, then, only if a supplier is picked and "On account" is
  /// chosen, records what's owed against [movement] via
  /// [SupplierCreditRepository.recordStockPurchaseOnCredit]. A cost
  /// price left blank passes `null` through to
  /// [ProductRepository.updateProduct], which treats that as "leave
  /// alone" — never a silent reset to 0.
  Future<void> _recordCostAndCredit({
    required Product product,
    required int quantity,
    required StockMovement movement,
  }) async {
    final costPriceInput = double.tryParse(_costPriceController.text.trim());
    final supplierChanged = _supplierId != null && _supplierId != product.supplierId;
    if (costPriceInput != null || supplierChanged) {
      await ref.read(productRepositoryProvider).updateProduct(
            localId: product.localId,
            costPrice: costPriceInput,
            supplierId: supplierChanged ? _supplierId : null,
          );
    }
    if (_supplierId != null && _onAccount) {
      await ref.read(supplierCreditRepositoryProvider).recordStockPurchaseOnCredit(
            supplierLocalId: _supplierId!,
            amount: (costPriceInput ?? 0) * quantity,
            stockMovementLocalId: movement.localId,
          );
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
                                  onTap: () => setState(() {
                                    _product = item.product;
                                    _seedFromProduct(item.product);
                                  }),
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
    final suppliersAsync = ref.watch(suppliersProvider);
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
                _creditError = null;
              }),
            ),
            FulusChip(
              label: 'Stock out',
              selected: _type == StockMovementType.stockOut,
              onTap: () => setState(() {
                _type = StockMovementType.stockOut;
                _quantityError = null;
                _creditError = null;
              }),
            ),
            FulusChip(
              label: 'Adjustment',
              selected: _type == StockMovementType.adjustment,
              onTap: () => setState(() {
                _type = StockMovementType.adjustment;
                _quantityError = null;
                _creditError = null;
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
        if (_type == StockMovementType.stockIn) ...[
          const SizedBox(height: AppSpacing.lg),
          FulusTextField(
            label: 'Cost price (optional)',
            controller: _costPriceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            helperText: "Updates this product's cost price.",
            errorText: _creditError,
            onChanged: (_) {
              if (_creditError != null) setState(() => _creditError = null);
            },
          ),
          suppliersAsync.when(
            data: (suppliers) => suppliers.isEmpty
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: AppSpacing.lg),
                      FulusDropdownField<String?>(
                        label: 'Supplier (optional)',
                        value: _supplierId,
                        options: [
                          const FulusDropdownOption(value: null, label: 'None'),
                          for (final s in suppliers) FulusDropdownOption(value: s.localId, label: s.name),
                        ],
                        onChanged: (value) => setState(() {
                          _supplierId = value;
                          if (value == null) _onAccount = false;
                        }),
                      ),
                      // "Paid now" vs "on account" only makes sense once a
                      // supplier is actually picked — recordStockPurchaseOnCredit
                      // needs one to attach the ledger entry to.
                      if (_supplierId != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        FulusChipRow(
                          children: [
                            FulusChip(
                              label: 'Paid now',
                              selected: !_onAccount,
                              onTap: () => setState(() {
                                _onAccount = false;
                                _creditError = null;
                              }),
                            ),
                            FulusChip(
                              label: 'On account',
                              selected: _onAccount,
                              onTap: () => setState(() => _onAccount = true),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
            loading: () => const SizedBox.shrink(),
            error: (e, _) => const SizedBox.shrink(),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        FulusButton(label: 'Save', loading: _submitting, onPressed: _submitting ? null : _submit),
      ],
    );
  }
}
