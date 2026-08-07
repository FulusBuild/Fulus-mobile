import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/receipt.dart';

/// Volume 5's "Confirming the Sale & Receipt" moment. Deliberately just
/// a share/print trigger, not a full printer pairing flow — sending
/// bytes to a physical Bluetooth printer is Device Services (Stage 15,
/// not built yet). What this DOES do fully: build the PDF and hand it
/// to the Android Share Sheet, which covers WhatsApp/email/"any app
/// that accepts a PDF" today without waiting on Stage 15 at all.
class ReceiptPreviewSheet extends ConsumerStatefulWidget {
  const ReceiptPreviewSheet({super.key, required this.saleId});

  final String saleId;

  static Future<void> show(BuildContext context, String saleId) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => ReceiptPreviewSheet(saleId: saleId),
    );
  }

  @override
  ConsumerState<ReceiptPreviewSheet> createState() => _ReceiptPreviewSheetState();
}

class _ReceiptPreviewSheetState extends ConsumerState<ReceiptPreviewSheet> {
  // Cached in initState rather than called inline in build() — see the
  // same note in home_screen.dart / employees_list_screen.dart / this
  // session's audit fixes for why a repository call directly inside
  // build() is the wrong place for it.
  late final Future<ReceiptData> _receiptFuture =
      ref.read(receiptRepositoryProvider).buildReceiptData(widget.saleId);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Receipt', style: AppTypography.heading),
            const SizedBox(height: AppSpacing.md),
            FutureBuilder<ReceiptData>(
              future: _receiptFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final data = snapshot.data!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data.invoiceNumber, style: AppTypography.body),
                    Text('${data.currencySymbol}${data.total.toStringAsFixed(2)}', style: AppTypography.display),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.share_outlined),
                            label: const Text('Share PDF'),
                            onPressed: () => _sharePdf(data),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.print_outlined),
                            label: const Text('Print'),
                            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Pair a printer in Settings to print directly (coming soon).')),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sharePdf(ReceiptData data) async {
    final repo = ref.read(receiptRepositoryProvider);
    final pdf = await repo.renderPdf(data);
    final path = await repo.writeToTempFile(pdf);
    await Share.shareXFiles([XFile(path)], text: 'Receipt ${data.invoiceNumber}');
  }
}
