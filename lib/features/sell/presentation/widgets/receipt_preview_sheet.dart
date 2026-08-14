import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app/providers.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/receipt.dart';

/// Volume 5's "Confirming the Sale & Receipt" moment.
///
/// Gap fix: this header comment used to say printing "sending bytes to
/// a physical Bluetooth printer is Device Services (Stage 15, not built
/// yet)" — stale; Stage 15 is complete (PrinterRepository,
/// ReceiptPrinterService, full ESC/POS building), it just had no caller
/// anywhere in the UI, so the Print button below did nothing but show
/// "coming soon." It now renders real thermal bytes via
/// ReceiptRepository.renderThermal (already existed, also uncalled) and
/// sends them to whichever printer PrinterRepository.getDefault()
/// returns. Printing failing never blocks anything else here — the
/// receipt is already fully rendered above regardless (Volume 12's
/// "printer unavailable... never blocks the sale," satisfied by this
/// screen's own existing structure, not something this fix needed to
/// add).
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
                            onPressed: () => _print(context, data),
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

  Future<void> _print(BuildContext context, ReceiptData data) async {
    final defaultPrinter = await ref.read(printerRepositoryProvider).getDefault();
    if (defaultPrinter == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No printer paired yet — add one from More → Settings → Printers.')),
        );
      }
      return;
    }
    try {
      final thermal = await ref.read(receiptRepositoryProvider).renderThermal(data);
      await ref.read(receiptPrinterServiceProvider).printToDefault(Uint8List.fromList(thermal.bytes));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sent to printer.')));
      }
    } on DeviceFailure catch (f) {
      // Never blocks anything — the receipt above is already fully
      // rendered and shareable regardless of whether this succeeds.
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(f.message)));
      }
    }
  }
}
