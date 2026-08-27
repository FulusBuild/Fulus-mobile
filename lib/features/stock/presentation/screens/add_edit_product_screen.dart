import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/screen_exit.dart';
import '../../../../domain/entities/product.dart';
import '../../../money/presentation/providers/money_providers.dart' show moneyCurrencySymbolProvider;
import '../../../../shared/screens/barcode_scan_screen.dart';
import '../../../../shared/screens/photo_capture_screen.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../application/stock_providers.dart';
import '../widgets/stock_error_banner.dart';

/// Volume 6, "Adding & Managing Products": "Add Product opens with just
/// Name and Price visible; every other field... one tap away under
/// 'More details,' never shown by default. Editing an existing product
/// is the same screen, pre-filled." One widget for both, per that exact
/// sentence — [existingProduct] null means Add, non-null means Edit.
///
/// No SKU field anywhere on this form — deliberate, not an oversight:
/// the Bible never lists SKU in the Product Model table, and states its
/// own reasoning directly elsewhere: "If a feature can only be reached
/// by first learning what 'SKU'... means, it doesn't belong in this
/// product." [ProductDraft.sku] is required by the repository layer
/// regardless (a real backend/domain requirement, not a Bible field),
/// so this screen generates one internally — see [_generateSku].
class AddEditProductScreen extends ConsumerStatefulWidget {
  const AddEditProductScreen({super.key, this.existingProduct});

  final Product? existingProduct;

  bool get isEditing => existingProduct != null;

  @override
  ConsumerState<AddEditProductScreen> createState() => _AddEditProductScreenState();
}

class _AddEditProductScreenState extends ConsumerState<AddEditProductScreen> {
  late final _nameController = TextEditingController(text: widget.existingProduct?.name ?? '');
  late final _priceController =
      TextEditingController(text: widget.existingProduct?.sellingPrice.toStringAsFixed(2) ?? '');
  late final _barcodeController = TextEditingController(text: widget.existingProduct?.barcode ?? '');
  late final _costController =
      TextEditingController(text: _nullIfZero(widget.existingProduct?.costPrice)?.toStringAsFixed(2) ?? '');
  late final _unitController = TextEditingController(text: widget.existingProduct?.unit ?? 'piece');
  late final _thresholdController =
      TextEditingController(text: (widget.existingProduct?.lowStockThreshold ?? 10).toString());
  late final _initialStockController = TextEditingController(text: '0');
  late String? _photoPath = widget.existingProduct?.photoPath;

  late String? _categoryId = widget.existingProduct?.categoryId;
  late String? _supplierId = widget.existingProduct?.supplierId;
  late bool _tracksStock = widget.existingProduct?.tracksStock ?? true;
  bool _moreDetailsOpen = false;
  bool _submitting = false;
  String? _bannerMessage;
  Map<String, String> _fieldErrors = {};

  static double? _nullIfZero(double? value) => (value == null || value == 0) ? null : value;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _barcodeController.dispose();
    _costController.dispose();
    _unitController.dispose();
    _thresholdController.dispose();
    _initialStockController.dispose();
    super.dispose();
  }

  void _clearErrors() {
    if (_bannerMessage != null || _fieldErrors.isNotEmpty) {
      setState(() {
        _bannerMessage = null;
        _fieldErrors = {};
      });
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final price = double.tryParse(_priceController.text.trim());
    final errors = <String, String>{};
    if (name.isEmpty) errors['name'] = 'Give this product a name.';
    if (price == null || price <= 0) {
      final currencySymbol = ref.read(moneyCurrencySymbolProvider).value ?? '₦';
      errors['price'] = "Price can't be ${currencySymbol}0.";
    }

    final cost = double.tryParse(_costController.text.trim());
    final threshold = int.tryParse(_thresholdController.text.trim()) ?? 10;
    final initialStock = int.tryParse(_initialStockController.text.trim()) ?? 0;

    if (errors.isNotEmpty) {
      setState(() => _fieldErrors = errors);
      return;
    }

    setState(() {
      _submitting = true;
      _bannerMessage = null;
      _fieldErrors = {};
    });

    try {
      final locationId = await ref.read(currentLocationIdProvider.future);
      final productRepo = ref.read(productRepositoryProvider);

      if (widget.isEditing) {
        final existing = widget.existingProduct!;
        await productRepo.updateProduct(
          localId: existing.localId,
          name: name,
          barcode: _barcodeController.text.trim().isEmpty ? null : _barcodeController.text.trim(),
          categoryId: _categoryId,
          supplierId: _supplierId,
          costPrice: cost ?? 0,
          sellingPrice: price!,
          lowStockThreshold: threshold,
        );
        await productRepo.setLocalOverrides(
          productLocalId: existing.localId,
          tracksStock: _tracksStock,
          unit: _unitController.text.trim().isEmpty ? 'piece' : _unitController.text.trim(),
          photoPath: _photoPath,
        );
      } else {
        final sku = await _generateSku(name);
        final created = await productRepo.createProduct(
          ProductDraft(
            name: name,
            sku: sku,
            costPrice: cost ?? 0,
            sellingPrice: price!,
            locationId: locationId,
            barcode: _barcodeController.text.trim().isEmpty ? null : _barcodeController.text.trim(),
            categoryId: _categoryId,
            supplierId: _supplierId,
            lowStockThreshold: threshold,
            initialStock: initialStock,
          ),
        );
        await productRepo.setLocalOverrides(
          productLocalId: created.localId,
          tracksStock: _tracksStock,
          unit: _unitController.text.trim().isEmpty ? 'piece' : _unitController.text.trim(),
          photoPath: _photoPath,
        );
      }

      if (!mounted) return;
      showFulusSnackbar(context, message: widget.isEditing ? 'Product updated.' : 'Product added.');
      // FIX (onboarding audit): reached both via a normal go_router
      // route (Stock tab) AND via a raw Navigator.push from
      // AddFirstProductScreen (onboarding). A bare `context.pop()` only
      // pops go_router's own stack — for the onboarding caller that has
      // nothing to pop, so it threw `GoError: There is nothing to pop`,
      // landing in the catch-all below and showing a false "couldn't
      // save" banner on top of a save that had already succeeded.
      // closeScreenOr handles both callers correctly.
      context.closeScreenOr('/');
    } on ValidationFailure catch (v) {
      if (!mounted) return;
      setState(() => _fieldErrors = v.fieldErrors);
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() => _bannerMessage = f.message);
    } catch (_) {
      // ProductRepositoryImpl's createProduct/updateProduct/
      // setLocalOverrides don't actually throw Failure today (a local
      // Drift write, not yet routed through the Business Engine's error
      // hierarchy) — the two typed catches above are ready for when
      // they do, but nothing currently reaches them. This is the real
      // fallback: a rare local write error (a SKU collision surviving
      // all 20 retry attempts, a database constraint) still needs to
      // land on the banner instead of failing silently with the button
      // just going quiet.
      if (!mounted) return;
      setState(() => _bannerMessage = "Couldn't save this product. Try again.");
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Volume 6 never surfaces SKU as something a person types — see this
  /// file's own header comment. Generated from the name (short, human-
  /// recognizable prefix) plus a random suffix, checked against
  /// [ProductRepository.getAllSkus] — the exact method that interface's
  /// own doc comment says exists for precisely this kind of uniqueness
  /// check.
  Future<String> _generateSku(String name) async {
    final prefix = name.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '').padRight(3, 'X').substring(0, 3);
    final existing = await ref.read(productRepositoryProvider).getAllSkus();
    final random = Random();
    for (var attempt = 0; attempt < 20; attempt++) {
      final suffix = (1000 + random.nextInt(9000)).toString();
      final candidate = '$prefix-$suffix';
      if (!existing.contains(candidate)) return candidate;
    }
    // 20 collisions against a 9000-value space is astronomically
    // unlikely — this fallback exists so the function still has a
    // total, honest return value rather than an unreachable-in-practice
    // assumption with no way out.
    return '$prefix-${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final suppliersAsync = ref.watch(suppliersProvider);

    return FulusScreen(
      title: widget.isEditing ? 'Edit product' : 'Add product',
      body: ListView(
        children: [
          if (_bannerMessage != null) ...[
            StockErrorBanner(message: _bannerMessage!),
            const SizedBox(height: AppSpacing.lg),
          ],
          FulusTextField(
            label: 'Name',
            controller: _nameController,
            errorText: _fieldErrors['name'],
            onChanged: (_) => _clearErrors(),
          ),
          const SizedBox(height: AppSpacing.lg),
          FulusTextField(
            label: 'Price',
            controller: _priceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            errorText: _fieldErrors['price'],
            onChanged: (_) => _clearErrors(),
          ),
          const SizedBox(height: AppSpacing.lg),
          FulusButton(
            label: _moreDetailsOpen ? 'Hide more details' : 'More details',
            variant: FulusButtonVariant.text,
            icon: _moreDetailsOpen ? Icons.expand_less : Icons.expand_more,
            onPressed: () => setState(() => _moreDetailsOpen = !_moreDetailsOpen),
          ),
          if (_moreDetailsOpen) ...[
            const SizedBox(height: AppSpacing.sm),
            FulusTextField(
              label: 'Barcode',
              controller: _barcodeController,
              suffixIcon: IconButton(
                icon: const Icon(Icons.qr_code_scanner_outlined),
                tooltip: 'Scan barcode',
                onPressed: () async {
                  final scanned = await BarcodeScanScreen.scan(context, title: 'Scan product barcode');
                  if (scanned != null) _barcodeController.text = scanned;
                },
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Photo', style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context), fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                if (_photoPath != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(File(_photoPath!), width: 64, height: 64, fit: BoxFit.cover),
                  )
                else
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceOf(context),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.image_outlined, color: AppColors.textSecondaryOf(context)),
                  ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: FulusButton(
                    label: _photoPath == null ? 'Take photo' : 'Retake photo',
                    variant: FulusButtonVariant.secondary,
                    onPressed: () async {
                      final path = await PhotoCaptureScreen.capture(context, title: 'Photo this product');
                      if (path != null) setState(() => _photoPath = path);
                    },
                  ),
                ),
                if (_photoPath != null)
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Remove photo',
                    onPressed: () => setState(() => _photoPath = null),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            categoriesAsync.when(
              data: (categories) => FulusDropdownField<String?>(
                label: 'Category',
                value: _categoryId,
                options: [
                  const FulusDropdownOption(value: null, label: 'Uncategorized'),
                  for (final c in categories) FulusDropdownOption(value: c.localId, label: c.name),
                ],
                onChanged: (value) => setState(() => _categoryId = value),
              ),
              loading: () => const SizedBox.shrink(),
              error: (e, _) => const SizedBox.shrink(),
            ),
            const SizedBox(height: AppSpacing.lg),
            suppliersAsync.when(
              data: (suppliers) => suppliers.isEmpty
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                      child: FulusDropdownField<String?>(
                        label: 'Supplier',
                        value: _supplierId,
                        options: [
                          const FulusDropdownOption(value: null, label: 'None'),
                          for (final s in suppliers) FulusDropdownOption(value: s.localId, label: s.name),
                        ],
                        onChanged: (value) => setState(() => _supplierId = value),
                      ),
                    ),
              loading: () => const SizedBox.shrink(),
              error: (e, _) => const SizedBox.shrink(),
            ),
            FulusTextField(
              label: 'Cost price',
              controller: _costController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              helperText: 'Optional — enables margin on reports.',
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Track stock for this product',
                    style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context)),
                  ),
                ),
                Switch(value: _tracksStock, onChanged: (v) => setState(() => _tracksStock = v)),
              ],
            ),
            if (_tracksStock) ...[
              const SizedBox(height: AppSpacing.lg),
              FulusTextField(
                label: 'Unit',
                controller: _unitController,
                helperText: 'e.g. piece, kg, liter, dozen',
              ),
              const SizedBox(height: AppSpacing.lg),
              FulusTextField(
                label: 'Low stock threshold',
                controller: _thresholdController,
                keyboardType: TextInputType.number,
              ),
              if (!widget.isEditing) ...[
                const SizedBox(height: AppSpacing.lg),
                FulusTextField(
                  label: 'Starting stock',
                  controller: _initialStockController,
                  keyboardType: TextInputType.number,
                  helperText: 'How many you already have on hand.',
                ),
              ],
            ],
          ],
          const SizedBox(height: AppSpacing.xl),
          FulusButton(
            label: widget.isEditing ? 'Save changes' : 'Add product',
            loading: _submitting,
            onPressed: _submitting ? null : _save,
          ),
        ],
      ),
    );
  }
}
