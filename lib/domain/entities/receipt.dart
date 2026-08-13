/// Receipts — Stage 9.
///
/// [ReceiptData] is the single, format-agnostic input to the receipt
/// business engine (domain/usecases/receipt_engine.dart). It exists so
/// that ReceiptEngine never has to know about a Sale, a Customer, or a
/// BusinessSettings row directly — those belong to Stages 4-8's schema,
/// which this module doesn't own and shouldn't assume the exact shape
/// of. The data-layer repository implementation is the only place that
/// reads Stage 4-8 tables and assembles a ReceiptData from them; if
/// their column names differ from what's assumed there, only that one
/// mapping function needs adjusting; this file and receipt_engine.dart
/// do not.
///
/// Field set is the union of what backend/app/utils/pdf_invoice.py (A4
/// PDF) and frontend/lib/receipt.ts (58mm ESC/POS thermal) both need —
/// verified directly against both, since the Bible ("Receipt layout
/// should match backend behaviour") gives no reason to drop anything
/// either format already prints today.
class ReceiptData {
  const ReceiptData({
    required this.businessName,
    this.businessAddress,
    this.businessPhone,
    this.businessTin,
    required this.vatEnabled,
    required this.vatRate,
    this.cashierName,
    required this.invoiceNumber,
    required this.saleDate,
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.amountPaid,
    required this.paymentStatus,
    this.paymentMethod,
    this.customerName,
    this.customerPhone,
    this.customerEmail,
    this.customerAddress,
    this.notes,
    this.receiptFooter,
    required this.currencySymbol,
  });

  final String businessName;
  final String? businessAddress;
  final String? businessPhone;
  final String? businessTin;
  final bool vatEnabled;
  final double vatRate;
  final String? cashierName;

  final String invoiceNumber;
  final DateTime saleDate;
  final List<ReceiptLineItem> items;

  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final double amountPaid;

  /// paid | partial | unpaid | cancelled — mirrors Sale.payment_status
  /// exactly (pdf_invoice.py's status_color map and receipt.ts's
  /// balanceDue-driven display both key off this same vocabulary).
  final String paymentStatus;
  final String? paymentMethod;

  final String? customerName;
  final String? customerPhone;
  final String? customerEmail;
  final String? customerAddress;

  /// Cancelled-sale notes are filtered out before this reaches
  /// ReceiptData — pdf_invoice.py's own rule ("not sale.notes.startswith
  /// ('[CANCELLED')") is applied by the repository/mapper, not here, so
  /// this field is always safe to print as-is when non-null.
  final String? notes;
  final String? receiptFooter;

  /// The business's configured symbol as typed in Settings (e.g. "₦",
  /// "$", "GHS"), NOT yet made printer-safe — ReceiptEngine's ESC/POS
  /// builder does that substitution itself (see currency_symbol handling
  /// note in receipt_engine.dart), matching receipt.ts's own division of
  /// responsibility between the data shape and the print-time formatter.
  final String currencySymbol;

  /// total - amountPaid, floored at 0 — mirrors Sale.balance_due exactly
  /// (a computed backend @property, never a stored column, per
  /// pdf_invoice.py's own comment on why).
  double get balanceDue {
    final due = total - amountPaid;
    return due > 0 ? due : 0;
  }

  /// Bug fix (business-logic audit): added alongside balanceDue above,
  /// which only ever moves in one direction (floored at 0, so an
  /// overpayment just silently reads as balanceDue: 0 with nothing
  /// noting the difference). Every receipt-rendering call site checked
  /// `balanceDue > 0` for a "Balance due" line but had no symmetric
  /// check for the opposite case — a cash sale where the customer
  /// handed over more than the total is completely ordinary and this
  /// receipt is often the cashier's own record of how much change was
  /// actually given.
  double get changeDue {
    final change = amountPaid - total;
    return change > 0 ? change : 0;
  }
}

class ReceiptLineItem {
  const ReceiptLineItem({
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  final String productName;
  final int quantity;
  final double unitPrice;
  final double lineTotal;
}

enum ReceiptFormat { thermalEscPos, pdfA4 }

/// The engine's output — raw bytes plus enough metadata for the
/// repository/UI to decide a filename and MIME type without re-deriving
/// them from the format enum in more than one place.
class GeneratedReceipt {
  const GeneratedReceipt({
    required this.format,
    required this.bytes,
    required this.suggestedFileName,
    required this.mimeType,
  });

  final ReceiptFormat format;
  final List<int> bytes;
  final String suggestedFileName;
  final String mimeType;
}
