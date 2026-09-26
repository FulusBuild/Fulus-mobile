import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';

/// Bulk-import screen for `ImportProductsFromCsv`. Supports picking a
/// .csv file or pasting spreadsheet content directly — both paths feed
/// the same [_contentController], since the usecase takes raw CSV text
/// rather than a file path or handle.
///
/// No column-mapping step: ProductImportEngine expects fixed header
/// names (name/selling_price required; sku optional and auto-generated
/// when omitted, matching AddEditProductScreen). This screen's format
/// guide shows that shape up front and catches mismatches on Review,
/// rather than offering a remapping capability the engine doesn't have.
class BulkImportScreen extends ConsumerStatefulWidget {
  const BulkImportScreen({super.key});

  @override
  ConsumerState<BulkImportScreen> createState() => _BulkImportScreenState();
}

class _BulkImportScreenState extends ConsumerState<BulkImportScreen> {
  final _contentController = TextEditingController();
  bool _picking = false;

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    setState(() => _picking = true);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (result.isEmpty) return;
      final bytes = await result.single.readAsBytes();
      _contentController.text = utf8.decode(bytes, allowMalformed: true);
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      showFulusSnackbar(context, message: "Couldn't read that file. Try pasting its contents instead.");
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FulusScreen(
      title: 'Bulk import products',
      subtitle: 'Add many products from a CSV file',
      body: ListView(
        children: [
          FulusCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.primaryOf(context).withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Icon(FulusIcons.upload, color: AppColors.primaryOf(context)),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Import format', style: AppTypography.subheading.copyWith(color: AppColors.textPrimaryOf(context))),
                          const SizedBox(height: 2),
                          Text(
                            'Prepare your spreadsheet before importing',
                            style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'First row is column names. Required: name, selling_price. '
                  "Optional: sku, barcode, cost_price, category, supplier, "
                  'initial_stock, low_stock_threshold. Leave sku blank (or leave '
                  "out the column) and Fulus will generate one for you — same as "
                  'adding a product one at a time.',
                  style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundOf(context),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: AppColors.borderOf(context)),
                  ),
                  child: Text(
                    'name,sku,selling_price,cost_price,initial_stock\n'
                    'Bag of rice 50kg,RICE50,45000,38000,12',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondaryOf(context),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          FulusActionTile(
            icon: FulusIcons.upload,
            title: 'Choose a .csv file',
            subtitle: _picking ? 'Reading your file…' : 'Select a spreadsheet export from this device.',
            trailing: _picking ? const FulusLoadingIndicator() : null,
            onTap: _picking ? null : _pickFile,
          ),
          const SizedBox(height: AppSpacing.lg),
          const FulusSectionHeader(
            title: 'Or paste manually',
            subtitle: 'Paste the exported CSV text if you already have it copied',
          ),
          FulusTextField(
            label: 'CSV content',
            controller: _contentController,
            maxLines: 10,
            hintText: 'Paste the full contents of your spreadsheet export here…',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),
          FulusActionTile(
            icon: FulusIcons.chevronRight,
            title: 'Continue to review',
            subtitle: _contentController.text.trim().isEmpty
                ? 'Paste or choose a CSV file first.'
                : 'Check the rows before adding them to Stock.',
            onTap: _contentController.text.trim().isEmpty
                ? null
                : () => context.pushNamed('stockBulkImportReview', extra: _contentController.text),
          ),
        ],
      ),
    );
  }
}
