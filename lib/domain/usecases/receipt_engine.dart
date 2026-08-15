import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../entities/receipt.dart';

/// Stage 9's pure-logic layer: turns a [ReceiptData] into bytes, in
/// either format. No dart:io — [ReceiptRepositoryImpl] is the only
/// place that writes the resulting bytes to a file. `package:pdf` is
/// pure Dart (unlike `printing`, its Flutter-facing companion), so
/// using it here doesn't break the "no Flutter in the business engine"
/// rule the Implementation Bible sets out.
class ReceiptEngine {
  const ReceiptEngine();

  /// Ported line-for-line from frontend/lib/receipt.ts's buildReceipt —
  /// see [MoneyFormatter] and [_ThermalBuilder] below for the two
  /// pieces of that file this splits into. 58mm width (32 cols),
  /// text-only, matching the original's own stated scope.
  GeneratedReceipt renderThermal(ReceiptData data) {
    final b = _ThermalBuilder()..init();
    final money = MoneyFormatter(data.currencySymbol);

    b.align(_Align.center).bold(true).doubleSize(true).line(data.businessName);
    b.doubleSize(false).bold(false);
    if (data.businessAddress != null) b.line(data.businessAddress!);
    if (data.businessPhone != null) b.line(data.businessPhone!);
    if (data.businessTin != null) b.line('TIN: ${data.businessTin}');
    b.line(data.invoiceNumber).line(_formatDate(data.saleDate));
    b.align(_Align.left).line('-' * _ThermalBuilder.width);

    for (final item in data.items) {
      b.line(item.productName);
      b.line(_padRow(
        '  ${item.quantity} x ${money.format(item.unitPrice)}',
        money.format(item.lineTotal),
      ));
    }

    b.line('-' * _ThermalBuilder.width);
    b.line(_padRow('Subtotal', money.format(data.subtotal)));
    if (data.discount > 0) {
      b.line(_padRow('Discount', '-${money.format(data.discount)}'));
    }
    if (data.vatEnabled) {
      if (data.tax > 0) {
        b.line(_padRow('VAT (${data.vatRate}%)', money.format(data.tax)));
      }
    } else if (data.tax > 0) {
      b.line(_padRow('Tax', money.format(data.tax)));
    }
    b.bold(true);
    b.line(_padRow('Total', money.format(data.total)));
    b.bold(false);
    b.line(_padRow('Paid', money.format(data.amountPaid)));
    if (data.balanceDue > 0) {
      b.line(_padRow('Balance due', money.format(data.balanceDue)));
    }
    if (data.changeDue > 0) {
      b.line(_padRow('Change given', money.format(data.changeDue)));
    }
    if (data.paymentMethod != null) b.line('Payment: ${data.paymentMethod}');
    if (data.cashierName != null) b.line('Cashier: ${data.cashierName}');

    b.feed(1).align(_Align.center).line(
        (data.receiptFooter?.isNotEmpty ?? false) ? data.receiptFooter! : 'Thank you for your business');
    b.cut();

    final bytes = b.build();
    return GeneratedReceipt(
      format: ReceiptFormat.thermalEscPos,
      bytes: bytes,
      suggestedFileName: '${data.invoiceNumber}.bin',
      mimeType: 'application/octet-stream',
    );
  }

  /// Ported from backend/app/utils/pdf_invoice.py's layout (header /
  /// invoice meta / customer / items table / totals / notes / footer),
  /// using `package:pdf`'s widget API in place of ReportLab's Platypus
  /// flowables. Colors and section order match 1:1; see inline notes
  /// for the handful of spots where a pdf-widgets idiom stands in for a
  /// ReportLab one.
  Future<GeneratedReceipt> renderPdf(ReceiptData data) async {
    final doc = pw.Document();
    final money = MoneyFormatter(data.currencySymbol, spaceBeforeAmount: false, forcePrefix: true);

    const blue = PdfColor.fromInt(0xFF1D4ED8);
    const dark = PdfColor.fromInt(0xFF111827);
    const grey = PdfColor.fromInt(0xFF6B7280);
    const lightGrey = PdfColor.fromInt(0xFFF9FAFB);
    const red = PdfColor.fromInt(0xFFDC2626);
    const statusColors = {
      'paid': PdfColor.fromInt(0xFF16A34A),
      'partial': PdfColor.fromInt(0xFFD97706),
      'unpaid': PdfColor.fromInt(0xFFDC2626),
      'cancelled': PdfColor.fromInt(0xFF6B7280),
    };

    final showNotes = data.notes != null && !data.notes!.startsWith('[CANCELLED');

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20 * PdfPageFormat.mm),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(data.businessName,
                          style: pw.TextStyle(color: blue, fontSize: 20, fontWeight: pw.FontWeight.bold)),
                      if (data.businessAddress != null)
                        pw.Text(data.businessAddress!, style: pw.TextStyle(color: grey, fontSize: 9)),
                      if (data.businessPhone != null)
                        pw.Text(data.businessPhone!, style: pw.TextStyle(color: grey, fontSize: 9)),
                    ],
                  ),
                  pw.Text('INVOICE', style: pw.TextStyle(color: dark, fontSize: 20, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.Divider(thickness: 2, color: blue),
              pw.SizedBox(height: 5 * PdfPageFormat.mm),

              // ── Invoice meta ────────────────────────────────────────
              _metaRow('Invoice Number:', data.invoiceNumber, grey, dark),
              _metaRow('Date:', _formatLongDate(data.saleDate), grey, dark),
              _metaRow('Payment Method:', data.paymentMethod ?? '—', grey, dark),
              pw.Row(children: [
                pw.SizedBox(
                  width: 45 * PdfPageFormat.mm,
                  child: pw.Text('Status:', style: pw.TextStyle(color: grey, fontSize: 10, fontWeight: pw.FontWeight.bold)),
                ),
                pw.Text(
                  data.paymentStatus.toUpperCase(),
                  style: pw.TextStyle(
                    color: statusColors[data.paymentStatus] ?? grey,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ]),
              pw.SizedBox(height: 8 * PdfPageFormat.mm),

              // ── Customer info ───────────────────────────────────────
              if (data.customerName != null) ...[
                pw.Text('Bill To:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.Text(data.customerName!, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                if (data.customerPhone != null) pw.Text('Phone: ${data.customerPhone}', style: const pw.TextStyle(fontSize: 10)),
                if (data.customerEmail != null) pw.Text('Email: ${data.customerEmail}', style: const pw.TextStyle(fontSize: 10)),
                if (data.customerAddress != null) pw.Text(data.customerAddress!, style: const pw.TextStyle(fontSize: 10)),
                pw.SizedBox(height: 6 * PdfPageFormat.mm),
              ],

              // ── Items table ─────────────────────────────────────────
              pw.Table(
                border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFE5E7EB), width: 0.5),
                columnWidths: const {
                  0: pw.FixedColumnWidth(10 * PdfPageFormat.mm),
                  1: pw.FlexColumnWidth(),
                  2: pw.FixedColumnWidth(20 * PdfPageFormat.mm),
                  3: pw.FixedColumnWidth(35 * PdfPageFormat.mm),
                  4: pw.FixedColumnWidth(35 * PdfPageFormat.mm),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: blue),
                    children: ['#', 'Product', 'Qty', 'Unit Price', 'Line Total']
                        .map((h) => pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text(h,
                                  textAlign: pw.TextAlign.center,
                                  style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10)),
                            ))
                        .toList(),
                  ),
                  for (var i = 0; i < data.items.length; i++)
                    pw.TableRow(
                      decoration: pw.BoxDecoration(color: i.isOdd ? lightGrey : PdfColors.white),
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('${i + 1}', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(data.items[i].productName, style: const pw.TextStyle(fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('${data.items[i].quantity}', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(money.format(data.items[i].unitPrice), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(money.format(data.items[i].lineTotal), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 9))),
                      ],
                    ),
                ],
              ),
              pw.SizedBox(height: 5 * PdfPageFormat.mm),

              // ── Totals ──────────────────────────────────────────────
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    _totalRow('Subtotal:', money.format(data.subtotal), grey, dark),
                    if (data.discount > 0) _totalRow('Discount:', '- ${money.format(data.discount)}', grey, dark),
                    if (data.tax > 0) _totalRow('Tax:', '+ ${money.format(data.tax)}', grey, dark),
                    pw.SizedBox(height: 2 * PdfPageFormat.mm),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(vertical: 2),
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(top: pw.BorderSide(color: blue), bottom: pw.BorderSide(color: blue)),
                      ),
                      child: _totalRow('TOTAL:', money.format(data.total), blue, blue, bold: true, fontSize: 12),
                    ),
                    _totalRow('Amount Paid:', money.format(data.amountPaid), grey, dark),
                    if (data.balanceDue > 0) _totalRow('Balance Due:', money.format(data.balanceDue), grey, red, bold: true),
                    if (data.changeDue > 0) _totalRow('Change Given:', money.format(data.changeDue), grey, dark, bold: true),
                  ],
                ),
              ),

              // ── Notes ───────────────────────────────────────────────
              if (showNotes) ...[
                pw.SizedBox(height: 6 * PdfPageFormat.mm),
                pw.RichText(
                  text: pw.TextSpan(children: [
                    pw.TextSpan(text: 'Notes: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: grey)),
                    pw.TextSpan(text: data.notes ?? '', style: pw.TextStyle(fontSize: 9, color: grey)),
                  ]),
                ),
              ],

              // ── Footer ──────────────────────────────────────────────
              pw.SizedBox(height: 12 * PdfPageFormat.mm),
              pw.Divider(thickness: 0.5, color: const PdfColor.fromInt(0xFFE5E7EB)),
              pw.SizedBox(height: 3 * PdfPageFormat.mm),
              pw.Center(
                child: pw.Text('Thank you for your business!', style: pw.TextStyle(fontSize: 9, color: grey)),
              ),
            ],
          );
        },
      ),
    );

    final bytes = await doc.save();
    return GeneratedReceipt(
      format: ReceiptFormat.pdfA4,
      bytes: bytes,
      suggestedFileName: '${data.invoiceNumber}.pdf',
      mimeType: 'application/pdf',
    );
  }

  pw.Widget _metaRow(String label, String value, PdfColor labelColor, PdfColor valueColor) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(children: [
        pw.SizedBox(
          width: 45 * PdfPageFormat.mm,
          child: pw.Text(label, style: pw.TextStyle(color: labelColor, fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ),
        pw.Text(value, style: pw.TextStyle(color: valueColor, fontSize: 10)),
      ]),
    );
  }

  pw.Widget _totalRow(String label, String value, PdfColor labelColor, PdfColor valueColor,
      {bool bold = false, double fontSize = 10}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.SizedBox(
            width: 40 * PdfPageFormat.mm,
            child: pw.Text(label,
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(color: labelColor, fontSize: fontSize, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ),
          pw.SizedBox(width: 4),
          pw.SizedBox(
            width: 40 * PdfPageFormat.mm,
            child: pw.Text(value,
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(color: valueColor, fontSize: fontSize, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String _formatLongDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  String _padRow(String left, String right) {
    final space = (_ThermalBuilder.width - left.length - right.length).clamp(1, 1 << 30);
    return left + (' ' * space) + right;
  }
}

enum _Align { left, center, right }

/// Port of receipt.ts's ReceiptBuilder — raw ESC/POS byte assembly.
/// Same command set, same behaviour, no printer transport of any kind
/// (that's Device Services, Stage 15, not built yet — this only
/// produces bytes).
class _ThermalBuilder {
  static const width = 32;
  static const _esc = 0x1b;
  static const _gs = 0x1d;

  final List<int> _bytes = [];

  _ThermalBuilder raw(List<int> values) {
    _bytes.addAll(values);
    return this;
  }

  /// Thermal printers overwhelmingly expect a single-byte code page
  /// rather than UTF-8 — same limitation and same fallback ('?' for
  /// anything outside 0-255) as receipt.ts's own text(), which covers
  /// invoice numbers, prices, and Latin-alphabet product names.
  _ThermalBuilder text(String line) {
    for (final rune in line.runes) {
      _bytes.add(rune < 256 ? rune : 0x3f);
    }
    return this;
  }

  _ThermalBuilder line([String text = '']) => this.text(text).raw([0x0a]);

  _ThermalBuilder init() => raw([_esc, 0x40]);

  _ThermalBuilder align(_Align mode) {
    final n = mode == _Align.center ? 1 : (mode == _Align.right ? 2 : 0);
    return raw([_esc, 0x61, n]);
  }

  _ThermalBuilder bold(bool on) => raw([_esc, 0x45, on ? 1 : 0]);

  _ThermalBuilder doubleSize(bool on) => raw([_gs, 0x21, on ? 0x11 : 0x00]);

  _ThermalBuilder feed([int lines = 1]) => raw(List.filled(lines, 0x0a));

  /// Feeds past the cutter then does a full cut — same widely-supported
  /// form receipt.ts uses, for the same reason (works across the most
  /// printer models without needing to know a specific feed-and-cut
  /// variant).
  _ThermalBuilder cut() => feed(3).raw([_gs, 0x56, 0x00]);

  Uint8Array build() => Uint8Array.fromList(_bytes);
}

/// Minimal typedef so this file doesn't need dart:typed_data's
/// Uint8List name leaking into the public API in a confusing way next
/// to dart:typed_data's own import above — GeneratedReceipt.bytes is
/// typed List<int>, which Uint8List already satisfies.
typedef Uint8Array = Uint8List;

/// Port of receipt.ts's currency handling — see that file's own
/// extensive comment (reproduced in spirit, not verbatim, below) for
/// why this exists at all: thermal printers can't render most Unicode
/// currency symbols, so a business's configured symbol is used as-is
/// when it's already printer-safe ASCII, the app's own non-ASCII
/// default (₦) maps to "NGN", and any OTHER non-ASCII symbol a business
/// explicitly chose prints with no currency label rather than a
/// confidently wrong one.
///
/// Made public (was `_MoneyFormatter`) for the nice-to-have receipt
/// preview redesign: receipt_preview_sheet.dart needs the exact same
/// thousands-formatted amounts this file prints, and duplicating the
/// formatting logic in two places risked the on-screen preview quietly
/// drifting from what actually gets printed/shared — a worse outcome
/// than one shared class crossing a file boundary. No behavior change,
/// every existing use within this file untouched.
class MoneyFormatter {
  MoneyFormatter(this._configuredSymbol, {this.spaceBeforeAmount = true, this.forcePrefix = false});

  final String? _configuredSymbol;
  final bool spaceBeforeAmount;

  /// PDF rendering has no printer code-page constraint at all (it's a
  /// real font, not a hardware code page) — [forcePrefix] lets
  /// [ReceiptEngine.renderPdf] print the configured symbol verbatim
  /// (matching pdf_invoice.py's hardcoded "₦" prefix) instead of
  /// applying the thermal-only safety fallback below.
  final bool forcePrefix;

  static const _knownFallbacks = {'₦': 'NGN'};

  bool _isPrinterSafe(String s) => s.runes.every((r) => r < 256);

  String _safeLabel() {
    final candidate = (_configuredSymbol ?? '').trim();
    if (forcePrefix) return candidate.isEmpty ? '₦' : candidate;
    if (candidate.isEmpty) return 'NGN';
    if (_isPrinterSafe(candidate)) return candidate;
    return _knownFallbacks[candidate] ?? '';
  }

  String format(double value) {
    final label = _safeLabel();
    final amount = _thousands(value);
    if (label.isEmpty) return amount;
    return spaceBeforeAmount ? '$label $amount' : '$label$amount';
  }

  String _thousands(double value) {
    final fixed = value.toStringAsFixed(2);
    final parts = fixed.split('.');
    final whole = parts[0];
    final negative = whole.startsWith('-');
    final digits = negative ? whole.substring(1) : whole;
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return '${negative ? '-' : ''}$buffer.${parts[1]}';
  }
}
