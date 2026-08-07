import 'package:equatable/equatable.dart';

/// Stage 15 — Device Services.
///
/// The two transports Stage 15's brief names for receipt printing —
/// "Bluetooth printers" and "USB printers." Kept as a flat two-value
/// enum rather than, say, a class hierarchy, because the ONLY place this
/// distinction actually matters is picking which concrete
/// ReceiptPrinter implementation handles a given PairedPrinter
/// (receipt_printer_service.dart) — everything downstream of that
/// (ESC/POS byte building, the ReceiptPrinter interface itself) is
/// already transport-agnostic by design.
enum PrinterTransport { bluetooth, usb }

/// A printer found during a scan — NOT yet paired/persisted. See
/// [PairedPrinter] for the persisted counterpart once an owner actually
/// chooses one (Volume 11: "Pairing, testing, and unpairing").
class PrinterDevice extends Equatable {
  const PrinterDevice({
    required this.name,
    required this.address,
    required this.transport,
  });

  /// The device's own advertised name (e.g. "MPT-II" for a common budget
  /// 58mm printer) — shown to the owner during pairing so they can tell
  /// which physical printer is which without needing to read a MAC
  /// address off a label.
  final String name;

  /// Bluetooth MAC address, or the USB device's identifying
  /// vendor/product/serial string — whichever [transport] implies. Not
  /// further typed/split, since neither ReceiptPrinter implementation
  /// needs to parse this itself; each simply hands its own transport's
  /// address format to its own underlying connection call.
  final String address;

  final PrinterTransport transport;

  @override
  List<Object?> get props => [name, address, transport];
}

/// A printer an owner has actually paired and this app remembers —
/// tables.dart's PairedPrinters is the persisted form this mirrors.
class PairedPrinter extends Equatable {
  const PairedPrinter({
    required this.id,
    required this.name,
    required this.address,
    required this.transport,
    required this.isDefault,
    required this.pairedAt,
  });

  final String id;
  final String name;
  final String address;
  final PrinterTransport transport;

  /// Volume 11: "setting the default that persists across restarts."
  /// Exactly one PairedPrinter should have this true at a time — enforced
  /// by PrinterRepository.setDefault (data/repositories/
  /// printer_repository_impl.dart), which clears every other row's flag
  /// in the same transaction, the same "one true row" discipline
  /// AuthRepositoryImpl._persistSession already uses for Sessions.
  final bool isDefault;

  final DateTime pairedAt;

  PrinterDevice toDevice() =>
      PrinterDevice(name: name, address: address, transport: transport);

  @override
  List<Object?> get props => [id, name, address, transport, isDefault, pairedAt];
}

/// A ReceiptPrinter implementation's current connection lifecycle state
/// — deliberately small and generic across both transports, since a
/// caller printing a receipt (future Sell checkout, Stage 7) shouldn't
/// need transport-specific states to react to "is this thing connected
/// right now."
enum PrinterConnectionState { disconnected, connecting, connected, error }
