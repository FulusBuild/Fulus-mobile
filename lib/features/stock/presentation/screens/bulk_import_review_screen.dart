import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/product_import.dart';
import '../../../../shared/widgets/widgets.dart';

/// Runs [ImportProductsFromCsv] and shows the result — Volume 6's
/// "Review" step. Errors are per-row and non-fatal to the rest of the
/// import, matching the usecase's own "never stop on first error"
/// design (that file's own header comment).
class BulkImportReviewScreen extends ConsumerStatefulWidget {
  const BulkImportReviewScreen({super.key, required this.csvContent});
  final String csvContent;

  @override
  ConsumerState<BulkImportReviewScreen> createState() => _BulkImportReviewScreenState();
}

class _BulkImportReviewScreenState extends ConsumerState<BulkImportReviewScreen> {
  late Future<ProductImportResult> _future = _run();

  Future<ProductImportResult> _run() async {
    final locationId = await ref.read(activeLocationIdProvider.future);
    final result = await ref.read(importProductsFromCsvProvider).call(
          csvContent: widget.csvContent,
          locationId: locationId,
        );
    // See dataRefreshSignalProvider's own doc comment in
    // app/providers.dart — same reasoning as AddEditProductScreen's
    // own save, just for a whole batch of new products at once.
    ref.read(dataRefreshSignalProvider.notifier).state++;
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return FulusScreen(
      title: 'Import results',
      subtitle: 'Review what was added and what needs fixing',
      body: FutureBuilder<ProductImportResult>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return FulusErrorState(
              message: "Couldn't run this import.",
              onRetry: () => setState(() {
                _future = _run();
              }),
            );
          }
          if (!snap.hasData) {
            return const FulusLoadingIndicator();
          }
          final result = snap.data!;
          return ListView(
            children: [
              FulusCard(
                child: Column(
                  children: [
                    Row(
                      children: [
                        _ResultIcon(
                          icon: result.errorCount == 0 ? FulusIcons.check : FulusIcons.warning,
                          color: result.errorCount == 0 ? AppColors.primaryOf(context) : AppColors.errorOf(context),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            result.errorCount == 0
                                ? 'Import completed successfully'
                                : '${result.successCount} added, ${result.errorCount} need attention',
                            style: AppTypography.subheading.copyWith(color: AppColors.textPrimaryOf(context)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _ResultStat(label: 'Added', value: result.successCount, color: AppColors.primaryOf(context)),
                        _ResultStat(label: 'Errors', value: result.errorCount, color: AppColors.errorOf(context)),
                        _ResultStat(label: 'Total rows', value: result.totalRows, color: AppColors.textSecondaryOf(context)),
                      ],
                    ),
                  ],
                ),
              ),
              if (result.errors.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                const FulusSectionHeader(
                  title: 'Rows that need fixing',
                  subtitle: 'Correct these rows in your source file before importing them again',
                ),
                for (final error in result.errors)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: FulusCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(FulusIcons.error, color: AppColors.errorOf(context), size: AppIconSize.compact),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              error.row == 0
                                  ? error.message
                                  : 'Row ${error.row}${error.field != null ? ' (${error.field})' : ''}: ${error.message}',
                              style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FulusButton(
                  label: 'Done',
                  icon: FulusIcons.check,
                  onPressed: () => context.goNamed('stock'),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          );
        },
      ),
    );
  }
}

class _ResultIcon extends StatelessWidget {
  const _ResultIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Icon(icon, color: color),
    );
  }
}

class _ResultStat extends StatelessWidget {
  const _ResultStat({required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('$value', style: AppTypography.display.copyWith(color: color)),
        Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
      ],
    );
  }
}
