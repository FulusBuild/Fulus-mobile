import 'dart:typed_data';

import '../../core/errors/failure.dart';
import '../../domain/entities/printer_device.dart';
import '../../domain/repositories/printer_repository.dart';
import 'bluetooth_receipt_printer.dart';
import 'escpos/escpos_commands.dart';
import 'receipt_printer.dart';
import 'usb_receipt_printer.dart';

/// Stage 15 — Device Services (Printing).
///
/// The one printing entry point everything outside device_services/
/// should depend on. Picks the correct [ReceiptPrinter] implementation
/// for a given [PairedPrinter]'s transport, and — for the common case —
/// resolves "the default printer" from [PrinterRepository] itself, so a
/// future checkout screen (Stage 7) can just call [printToDefault]
/// without knowing PrinterRepository, BluetoothReceiptPrinter, or
/// UsbReceiptPrinter exist at all. Matches this codebase's Repository
/// Pattern discipline: UI depends on one clean surface, not the
/// implementation choices behind it.
///
/// Connects fresh for each print and disconnects immediately after,
/// rather than holding a persistent connection across the app's
/// lifetime — Volume 5's own failure scenario ("Printer disconnected
/// mid-print: the sale is already complete before printing is
/// attempted, so a failed print never threatens the sale") already
/// assumes printing is a short-lived, best-effort operation layered on
/// top of an already-committed sale, not a connection this service needs
/// to keep healthy continuously in the background.
class ReceiptPrinterService {
  ReceiptPrinterService({required PrinterRepository printerRepository})
      : _printerRepository = printerRepository;

  final PrinterRepository _printerRepository;

  /// Volume 5: "print (if a printer was paired)" is one of three
  /// equally-weighted post-sale options, never a hard dependency — a
  /// caller should be ready to catch [DeviceFailure.notPaired] here and
  /// fall through to WhatsApp share or skip (Stage 7's own decision, not
  /// this service's), never treat it as a reason the sale itself failed.
  Future<void> printToDefault(Uint8List escPosBytes) async {
    final printer = await _printerRepository.getDefault();
    if (printer == null) {
      throw const DeviceFailure.notPaired(
        'No receipt printer is set up yet.',
      );
    }
    await printTo(printer, escPosBytes);
  }

  Future<void> printTo(PairedPrinter printer, Uint8List escPosBytes) async {
    final transport = _transportFor(printer.transport);
    try {
      await transport.connect(printer);
      await transport.printBytes(escPosBytes);
    } finally {
      // Swallowed deliberately: disconnect() failing here (e.g. the
      // socket was never actually opened because connect() itself threw)
      // must never replace whatever real error connect()/printBytes()
      // already raised — Dart's own finally-block semantics mean an
      // exception thrown in here would otherwise silently supersede the
      // original one, leaving a caller who catches DeviceFailure.
      // connectionFailed instead seeing some unrelated disconnect-time
      // error with no idea what actually went wrong.
      try {
        await transport.disconnect();
      } catch (_) {
        // Best-effort cleanup only — see comment above.
      }
      _disposeIfPossible(transport);
    }
  }

  /// Volume 11's "testing" step — connects, sends
  /// EscPosCommandBuilder.testPrint()'s fixed payload, disconnects. No
  /// separate code path from [printTo]; a test print IS a real print of
  /// a deliberately minimal payload, not a simulated dry run.
  Future<void> testPrint(PairedPrinter printer) async {
    await printTo(printer, EscPosCommandBuilder.testPrint());
  }

  ReceiptPrinter _transportFor(PrinterTransport transport) {
    return switch (transport) {
      PrinterTransport.bluetooth => BluetoothReceiptPrinter(),
      PrinterTransport.usb => UsbReceiptPrinter(),
    };
  }

  /// Both concrete implementations expose dispose() to close their
  /// StreamController (see each file's own doc comment) but the shared
  /// ReceiptPrinter interface deliberately doesn't declare it — a
  /// one-shot, connect-print-disconnect-dispose instance created fresh
  /// per call (this class's own stated design, above) has no other
  /// caller who'd need to keep listening to connectionState past this
  /// point, so this is the correct, single place that lifecycle ends.
  void _disposeIfPossible(ReceiptPrinter transport) {
    if (transport is BluetoothReceiptPrinter) transport.dispose();
    if (transport is UsbReceiptPrinter) transport.dispose();
  }
}
