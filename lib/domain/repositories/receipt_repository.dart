import '../entities/receipt.dart';

/// Stage 9. Assembles a [ReceiptData] from whatever Stage 5-8 (and
/// Stage 4 BusinessSettings) tables actually hold once merged, then
/// hands it to ReceiptEngine (domain/usecases/receipt_engine.dart) to
/// render. The repository implementation is deliberately the ONLY place
/// that touches those tables directly — see receipt.dart's own doc
/// comment on why.
abstract class ReceiptRepository {
  /// Builds the format-agnostic data for a sale's receipt. Throws
  /// [ReceiptDataUnavailable] (core/errors/module_failures.dart) if the
  /// sale can't be found — never returns a partially-filled ReceiptData.
  Future<ReceiptData> buildReceiptData(String saleId);

  /// Renders [data] as 58mm ESC/POS bytes, ready to send to a paired
  /// thermal printer via the (not-yet-built, Stage 15) Device Services
  /// layer. Pure — no I/O, delegates to ReceiptEngine.
  GeneratedReceipt renderThermal(ReceiptData data);

  /// Renders [data] as an A4 PDF — mirrors backend/app/utils/
  /// pdf_invoice.py's layout, for sharing/printing on a normal printer
  /// or via the Android Share Sheet. Async because PDF assembly (the
  /// `pdf` package) is comparatively heavier than the ESC/POS builder.
  Future<GeneratedReceipt> renderPdf(ReceiptData data);

  /// Writes [receipt].bytes to a temp file under the app's cache
  /// directory and returns the path, ready for share_plus's Share.
  /// shareXFiles or a print plugin to consume. The file is NOT
  /// persisted beyond the OS's own cache-clearing — receipts are
  /// regenerated on demand from the Sale record, never treated as their
  /// own source of truth.
  Future<String> writeToTempFile(GeneratedReceipt receipt);
}
