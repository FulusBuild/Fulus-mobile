import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';

/// Gap fix — Volume 6's "Bulk Import" (CSV path). `ImportProductsFromCsv`
/// was a complete, tested usecase with no screen calling it.
///
/// Paste-based, deliberately: this app has no file-picker package
/// (`file_picker` isn't a dependency, and this pass can't add one
/// without network access to fetch it), and hand-rolling raw Android
/// storage browsing without a compiler to verify scoped-storage
/// handling against is a real way to ship something broken. Pasting
/// works identically on every Android version, needs no storage
/// permission, and is a normal way to move a spreadsheet's contents on
/// a phone (copy from Sheets/Excel/a WhatsApp-shared file opened in
/// another app, paste here). `ImportProductsFromCsv.call` already takes
/// raw CSV text, not a file path, so this isn't a workaround — it's the
/// actual shape the usecase expects.
///
/// No column-mapping step: ProductImportEngine expects fixed header
/// names (name/sku/selling_price required), not arbitrary ones — Volume
/// 6's "CSV Mapping" screen would be building a remapping capability
/// the engine underneath doesn't have. This screen's format guide is
/// the honest equivalent: show the required shape up front, catch
/// mismatches on Review instead of pretending to remap them.
class BulkImportScreen extends ConsumerStatefulWidget {
  const BulkImportScreen({super.key});

  @override
  ConsumerState<BulkImportScreen> createState() => _BulkImportScreenState();
}

class _BulkImportScreenState extends ConsumerState<BulkImportScreen> {
  final _contentController = TextEditingController();

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
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
                  'First row is column names. Required: name, sku, selling_price. '
                  'Optional: barcode, cost_price, category, supplier, initial_stock, '
                  'low_stock_threshold.',
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
          FulusSectionHeader(title: 'Paste your CSV'),
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
