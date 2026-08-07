import 'dart:typed_data';

import '../../domain/entities/printer_device.dart';

/// Stage 15 — Device Services (Printing).
///
/// What bluetooth_receipt_printer.dart and usb_receipt_printer.dart both
/// implement, and the only printing-related type a future caller (Stage
/// 7's checkout flow; a Settings "test print" action) should ever
/// depend on directly — matching this codebase's own Repository Pattern
/// discipline ("UI must never know implementation") applied to a
/// hardware transport instead of a data source. ReceiptPrinterService
/// (receipt_printer_service.dart) is what actually picks which
/// implementation to construct, based on a PairedPrinter's own
/// `transport` field — callers depend on this interface, never on
/// BluetoothReceiptPrinter/UsbReceiptPrinter by name.
abstract class ReceiptPrinter {
  Stream<PrinterConnectionState> get connectionState;

  Future<void> connect(PairedPrinter printer);

  /// Sends already-built ESC/POS bytes (escpos/escpos_commands.dart) to
  /// the connected printer. Does not build receipt content itself —
  /// see EscPosCommandBuilder's own doc comment on why that boundary
  /// matters.
  Future<void> printBytes(Uint8List data);

  Future<void> disconnect();
}
