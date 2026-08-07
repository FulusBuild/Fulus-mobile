import 'dart:convert';

import 'package:fulus_mobile/domain/entities/receipt.dart';
import 'package:fulus_mobile/domain/usecases/receipt_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = ReceiptEngine();

  ReceiptData sample({String currencySymbol = '₦', double amountPaid = 1000, double total = 1000}) => ReceiptData(
        businessName: 'Adaeze Stores',
        businessAddress: '12 Market Rd, Lagos',
        businessPhone: '08012345678',
        vatEnabled: true,
        vatRate: 7.5,
        invoiceNumber: 'INV-0042',
        saleDate: DateTime(2026, 7, 30, 14, 5),
        items: const [
          ReceiptLineItem(productName: 'Rice 5kg', quantity: 2, unitPrice: 400, lineTotal: 800),
          ReceiptLineItem(productName: 'Milk', quantity: 1, unitPrice: 200, lineTotal: 200),
        ],
        subtotal: 1000,
        discount: 0,
        tax: 0,
        total: total,
        amountPaid: amountPaid,
        paymentStatus: 'paid',
        paymentMethod: 'Cash',
        currencySymbol: currencySymbol,
      );

  group('ReceiptData.balanceDue', () {
    test('is zero when fully paid', () {
      expect(sample(amountPaid: 1000, total: 1000).balanceDue, 0);
    });

    test('is the shortfall when partially paid', () {
      expect(sample(amountPaid: 600, total: 1000).balanceDue, 400);
    });

    test('never goes negative on overpayment', () {
      expect(sample(amountPaid: 1200, total: 1000).balanceDue, 0);
    });
  });

  group('renderThermal', () {
    test('produces non-empty ESC/POS bytes with the expected metadata', () {
      final receipt = engine.renderThermal(sample());
      expect(receipt.format, ReceiptFormat.thermalEscPos);
      expect(receipt.bytes, isNotEmpty);
      expect(receipt.suggestedFileName, 'INV-0042.bin');
      expect(receipt.mimeType, 'application/octet-stream');
    });

    test('printable text contains the business name, items, and total', () {
      final receipt = engine.renderThermal(sample());
      // ESC/POS control bytes are non-printable; decoding as latin1 and
      // stripping anything below 0x20 recovers just the text portions
      // that were written via text()/line(), which is enough to assert
      // on content without re-implementing the byte protocol here.
      final text = String.fromCharCodes(receipt.bytes.where((b) => b >= 0x20 && b < 0x7f));
      expect(text, contains('Adaeze Stores'));
      expect(text, contains('Rice 5kg'));
      expect(text, contains('INV-0042'));
      expect(text, contains('Total'));
    });

    test('omits the discount line entirely when there is no discount', () {
      final receipt = engine.renderThermal(sample());
      final text = String.fromCharCodes(receipt.bytes.where((b) => b >= 0x20 && b < 0x7f));
      expect(text, isNot(contains('Discount')));
    });

    test('falls back to "NGN" for the app default symbol on a thermal printer', () {
      final receipt = engine.renderThermal(sample(currencySymbol: '₦'));
      final text = String.fromCharCodes(receipt.bytes.where((b) => b >= 0x20 && b < 0x7f));
      expect(text, contains('NGN'));
    });

    test('prints an already-ASCII configured symbol as-is', () {
      final receipt = engine.renderThermal(sample(currencySymbol: '\$'));
      final text = String.fromCharCodes(receipt.bytes.where((b) => b >= 0x20 && b < 0x7f));
      expect(text, contains('\$'));
    });
  });

  group('renderPdf', () {
    test('produces bytes starting with the PDF magic header', () async {
      final receipt = await engine.renderPdf(sample());
      expect(receipt.format, ReceiptFormat.pdfA4);
      expect(receipt.mimeType, 'application/pdf');
      expect(ascii.decode(receipt.bytes.take(5).toList(), allowInvalid: true), '%PDF-');
    });

    test('suggested file name uses the invoice number', () async {
      final receipt = await engine.renderPdf(sample());
      expect(receipt.suggestedFileName, 'INV-0042.pdf');
    });
  });
}
