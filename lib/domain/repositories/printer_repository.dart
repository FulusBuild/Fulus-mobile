import '../entities/printer_device.dart';

/// Architecture Section 4's repository pattern, applied to Stage 15's
/// paired-printer persistence (Volume 11: "Pairing, testing, and
/// unpairing a receipt printer, plus setting the default that persists
/// across restarts"). Purely local — see tables.dart's PairedPrinters
/// doc comment on why this has no sync/server counterpart at all, not
/// even an optional one.
abstract class PrinterRepository {
  Stream<List<PairedPrinter>> watchPaired();

  /// The printer Sell's checkout (Stage 7, not this stage) should print
  /// to when the owner didn't pick one explicitly — null when nothing
  /// has been paired yet, which is a normal, expected state (Volume 3:
  /// "Printer Setup — Optional, Not a Blocker").
  Future<PairedPrinter?> getDefault();

  /// Pairs a newly-discovered device — the first one ever paired
  /// becomes the default automatically (a business's very first printer
  /// obviously should be), every later one does not, matching what an
  /// owner would actually expect without an extra "make default" tap on
  /// their first, and only, printer.
  Future<PairedPrinter> pair(PrinterDevice device);

  Future<void> unpair(String id);

  /// Clears every other row's isDefault first, in the same transaction
  /// — see PairedPrinter.isDefault's own doc comment on why exactly one
  /// row must hold this at a time.
  Future<void> setDefault(String id);
}
