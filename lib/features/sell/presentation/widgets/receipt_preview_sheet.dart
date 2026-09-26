import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app/providers.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/receipt.dart';
import '../../../../domain/usecases/receipt_engine.dart' show MoneyFormatter;
import '../../../../shared/widgets/widgets.dart';

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
///
/// Nice-to-have pass (direct product direction, not a Bible citation):
/// the body used to show only the invoice number and one large total —
/// every other field ReceiptData already carries (business header,
/// itemized lines, subtotal/discount/tax, payment method, change) was
/// already being rendered into the PDF/thermal output below, just never
/// shown on this screen itself before the person tapped Share/Print.
/// [_ReceiptSlip] closes that gap: a full itemized preview, styled to
/// read like a physical POS receipt (dashed section rules, an ITEM/QTY/
/// AMT table, a totals block) without literally reproducing a 32-column
/// thermal strip — this sheet has the full width of the screen to work
/// with and a proportional system font (Volume 16's own typography rule
/// is explicit that this app has "the system font... not a custom
/// typeface," so alignment here comes from Row/Expanded layout, the
/// same technique ReceiptEngine.renderPdf's own _totalRow/_metaRow
/// already use, not from monospace character padding).
///
/// Also closes a real, adjacent gap found while rebuilding this: the
/// FutureBuilder below only ever checked `snapshot.hasData` — a failed
/// ReceiptRepository.buildReceiptData call had no error branch at all,
/// so it would have spun on the loading indicator forever rather than
/// telling the person anything went wrong. Fixed alongside the redesign
/// since it's the same FutureBuilder being rebuilt regardless, using
/// this codebase's own established FulusErrorState + reload pattern
/// (transaction_detail_screen.dart's own `_future = ...` inside
/// `setState` is the direct precedent followed here).
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
  late Future<ReceiptData> _receiptFuture = _load();

  Future<ReceiptData> _load() => ref.read(receiptRepositoryProvider).buildReceiptData(widget.saleId);

  void _reload() => setState(() {
        _receiptFuture = _load();
      });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Receipt', style: AppTypography.heading.copyWith(color: AppColors.textPrimaryOf(context))),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: FutureBuilder<ReceiptData>(
                  future: _receiptFuture,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                        child: FulusErrorState(
                          message: "Couldn't load this receipt.",
                          reassurance: 'The sale itself is already saved — this is only about viewing it.',
                          onRetry: _reload,
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                        child: Center(child: FulusLoadingIndicator()),
                      );
                    }
                    final data = snapshot.data!;
                    return SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ReceiptSlip(data: data),
                          const SizedBox(height: AppSpacing.lg),
                          Row(
                            children: [
                              Expanded(
                                child: FulusButton(
                                  label: 'Share PDF',
                                  icon: FulusIcons.share,
                                  variant: FulusButtonVariant.secondary,
                                  onPressed: () => _sharePdf(data),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: FulusButton(
                                  label: 'Print',
                                  icon: FulusIcons.print,
                                  onPressed: () => _print(context, data),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sharePdf(ReceiptData data) async {
    final repo = ref.read(receiptRepositoryProvider);
    final pdf = await repo.renderPdf(data);
    final path = await repo.writeToTempFile(pdf);
    // SharePlus.instance.share() has open bugs on platforms this app
    // targets: broken entirely on Windows (plus_plugins#3619) and
    // throws/hangs on iOS 26 (plus_plugins#3685, #3631). Revisit once
    // those are resolved upstream.
    // ignore: deprecated_member_use
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

/// The itemized, paper-receipt-styled card — see this file's own header
/// comment for the reasoning behind the layout approach.
class _ReceiptSlip extends StatelessWidget {
  const _ReceiptSlip({required this.data});

  final ReceiptData data;

  @override
  Widget build(BuildContext context) {
    // Same formatting `MoneyFormatter` config renderPdf itself uses
    // (spaceBeforeAmount: false, forcePrefix: true) — this screen and
    // the PDF a person shares moments later should never show visibly
    // different numbers for the same sale.
    final money = MoneyFormatter(data.currencySymbol, spaceBeforeAmount: false, forcePrefix: true);
    final border = AppColors.borderOf(context);
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: border),
        boxShadow: AppElevation.cardOf(context),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Business header ──────────────────────────────────────
          Text(
            'FULUS',
            textAlign: TextAlign.center,
            style: AppTypography.label.copyWith(color: AppColors.primaryOf(context), letterSpacing: 2),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            data.businessName,
            textAlign: TextAlign.center,
            style: AppTypography.subheading.copyWith(color: textPrimary),
          ),
          if (data.businessAddress != null)
            Text(data.businessAddress!, textAlign: TextAlign.center, style: AppTypography.caption.copyWith(color: textSecondary)),
          if (data.businessPhone != null)
            Text(data.businessPhone!, textAlign: TextAlign.center, style: AppTypography.caption.copyWith(color: textSecondary)),
          const SizedBox(height: AppSpacing.md),
          _DashedDivider(color: border),
          const SizedBox(height: AppSpacing.sm),

          // ── Sale meta ─────────────────────────────────────────────
          Text('Receipt: ${data.invoiceNumber}', style: AppTypography.body.copyWith(color: textPrimary)),
          Text(_formatDateTime(data.saleDate), style: AppTypography.caption.copyWith(color: textSecondary)),
          if (data.cashierName != null)
            Text('Cashier: ${data.cashierName}', style: AppTypography.caption.copyWith(color: textSecondary)),
          const SizedBox(height: AppSpacing.sm),
          _DashedDivider(color: border),
          const SizedBox(height: AppSpacing.sm),

          // ── Items ─────────────────────────────────────────────────
          Row(
            children: [
              Expanded(flex: 5, child: Text('ITEM', style: AppTypography.label.copyWith(color: textSecondary))),
              Expanded(flex: 2, child: Text('QTY', textAlign: TextAlign.center, style: AppTypography.label.copyWith(color: textSecondary))),
              Expanded(flex: 3, child: Text('AMT', textAlign: TextAlign.right, style: AppTypography.label.copyWith(color: textSecondary))),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final item in data.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: Text(item.productName, style: AppTypography.body.copyWith(color: textPrimary))),
                  Expanded(
                    flex: 2,
                    child: Text('${item.quantity}', textAlign: TextAlign.center, style: AppTypography.body.copyWith(color: textPrimary)),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(money.format(item.lineTotal), textAlign: TextAlign.right, style: AppTypography.body.copyWith(color: textPrimary)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          _DashedDivider(color: border),
          const SizedBox(height: AppSpacing.sm),

          // ── Totals ────────────────────────────────────────────────
          _AmountRow(label: 'Subtotal', value: money.format(data.subtotal), color: textPrimary),
          if (data.discount > 0) _AmountRow(label: 'Discount', value: money.format(data.discount), color: textPrimary),
          if (data.tax > 0)
            _AmountRow(
              label: data.vatEnabled ? 'VAT (${_formatRate(data.vatRate)}%)' : 'Tax',
              value: money.format(data.tax),
              color: textPrimary,
            ),
          const SizedBox(height: AppSpacing.sm),
          _DashedDivider(color: border),
          const SizedBox(height: AppSpacing.sm),
          _AmountRow(label: 'TOTAL', value: money.format(data.total), color: textPrimary, emphasize: true),
          const SizedBox(height: AppSpacing.sm),
          _DashedDivider(color: border),
          const SizedBox(height: AppSpacing.sm),

          // ── Payment ───────────────────────────────────────────────
          // Feature: split-payment receipt breakdown — see
          // ReceiptData.paymentBreakdown's own doc comment. Replaces the
          // single "Payment: split" caption with one row per leg for
          // exactly the case that caption couldn't explain.
          if (data.paymentBreakdown != null && data.paymentBreakdown!.isNotEmpty)
            for (final leg in data.paymentBreakdown!)
              _AmountRow(label: leg.method, value: money.format(leg.amount), color: textPrimary)
          else if (data.paymentMethod != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text('Payment: ${data.paymentMethod}', style: AppTypography.caption.copyWith(color: textSecondary)),
            ),
          _AmountRow(label: 'Amount paid', value: money.format(data.amountPaid), color: textPrimary),
          if (data.changeDue > 0) _AmountRow(label: 'Change', value: money.format(data.changeDue), color: textPrimary),
          if (data.balanceDue > 0)
            _AmountRow(label: 'Balance due', value: money.format(data.balanceDue), color: AppColors.errorOf(context), emphasize: true),
          const SizedBox(height: AppSpacing.sm),
          _DashedDivider(color: border),
          const SizedBox(height: AppSpacing.md),

          // ── Footer ────────────────────────────────────────────────
          Text(
            (data.receiptFooter?.isNotEmpty ?? false) ? data.receiptFooter! : 'Thank you for shopping!',
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(color: textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('Powered by Fulus', textAlign: TextAlign.center, style: AppTypography.caption.copyWith(color: textSecondary)),
        ],
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({required this.label, required this.value, required this.color, this.emphasize = false});

  final String label;
  final String value;
  final Color color;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final style = (emphasize ? AppTypography.subheading : AppTypography.body).copyWith(color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          // Responsive UI audit — Flexible+ellipsis on the value side.
          Flexible(
            child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: style),
          ),
        ],
      ),
    );
  }
}

/// A thin horizontal dashed rule — the section separator every part of
/// the target layout uses between header/meta/items/totals/footer.
/// CustomPaint rather than a row of tiny Container children: a fixed
/// dash/gap pitch that draws cleanly at any width the surrounding
/// Column stretches it to, with no child-count arithmetic to get wrong.
class _DashedDivider extends StatelessWidget {
  const _DashedDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, 1),
      painter: _DashedLinePainter(color: color),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter({required this.color});

  final Color color;
  static const _dashWidth = 4.0;
  static const _dashSpace = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + _dashWidth, 0), paint);
      x += _dashWidth + _dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) => oldDelegate.color != color;
}

String _formatDateTime(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final day = d.day.toString().padLeft(2, '0');
  final hour = d.hour.toString().padLeft(2, '0');
  final minute = d.minute.toString().padLeft(2, '0');
  return '$day ${months[d.month - 1]} ${d.year} • $hour:$minute';
}

/// "7.5" prints as-is; "7.0" (or any whole number typed into Settings'
/// VAT rate field) prints as "7", not "7.0" — matches how a person
/// would naturally write either on a hand-written receipt.
String _formatRate(double rate) => rate == rate.roundToDouble() ? rate.toStringAsFixed(0) : rate.toString();
