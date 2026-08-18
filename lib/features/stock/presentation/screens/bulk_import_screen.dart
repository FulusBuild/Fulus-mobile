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
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );
      final bytes = result?.files.single.bytes;
      if (bytes == null) return; // canceled, or a picker that didn't return data
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
      body: ListView(
        children: [
          FulusCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Format', style: AppTypography.subheading.copyWith(color: AppColors.textPrimaryOf(context))),
                const SizedBox(height: AppSpacing.sm),
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
                    borderRadius: BorderRadius.circular(8),
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
          SizedBox(
            width: double.infinity,
            child: FulusButton(
              label: 'Choose a .csv file',
              icon: Icons.upload_file,
              variant: FulusButtonVariant.secondary,
              loading: _picking,
              onPressed: _picking ? null : _pickFile,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          FulusSectionHeader(title: 'Or paste manually'),
          FulusTextField(
            label: 'CSV content',
            controller: _contentController,
            maxLines: 10,
            hintText: 'Paste the full contents of your spreadsheet export here…',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FulusButton(
              label: 'Continue',
              onPressed: _contentController.text.trim().isEmpty
                  ? null
                  : () => context.pushNamed('stockBulkImportReview', extra: _contentController.text),
            ),
          ),
        ],
      ),
    );
  }
}
