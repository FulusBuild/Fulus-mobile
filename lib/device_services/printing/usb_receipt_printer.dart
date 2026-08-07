import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_usb_printer/flutter_usb_printer.dart';

import '../../core/errors/failure.dart';
import '../../domain/entities/printer_device.dart';
import 'receipt_printer.dart';

/// Stage 15 — Device Services (Printing), USB transport.
///
/// **Built without network/compiler access** — see
/// bluetooth_receipt_printer.dart's own opening note; the same
/// disclosure and the same "this package choice is isolated behind
/// ReceiptPrinter, swap it here alone if needed" reasoning applies here.
///
/// USB permission handling deliberately does NOT go through
/// device_permissions.dart/permission_handler: Android's USB host-mode
/// model is a different mechanism entirely from the runtime-permission
/// system permission_handler wraps. Attaching to a specific USB device
/// is authorized per-device, via a system dialog UsbManager itself
/// shows the first time this app requests that exact device (verified
/// against Android's own USB host documentation, not assumed) — there is
/// no app-level "USB permission" to pre-request the way there is for
/// camera or Bluetooth. flutter_usb_printer's connect call is expected
/// to trigger that native dialog itself.
class UsbReceiptPrinter implements ReceiptPrinter {
  UsbReceiptPrinter();

  final _plugin = FlutterUsbPrinter();

  final _stateController =
      StreamController<PrinterConnectionState>.broadcast();

  @override
  Stream<PrinterConnectionState> get connectionState => _stateController.stream;

  @override
  Future<void> connect(PairedPrinter printer) async {
    if (printer.transport != PrinterTransport.usb) {
      throw ArgumentError.value(
        printer.transport,
        'printer.transport',
        'UsbReceiptPrinter can only connect to a usb-transport '
            'PairedPrinter — the caller (ReceiptPrinterService) is '
            'responsible for dispatching by transport before reaching here.',
      );
    }

    _stateController.add(PrinterConnectionState.connecting);
    try {
      // address is stored as "vendorId:productId" (set by
      // PrinterDiscoveryService.scanUsb when the device was first
      // discovered) — split back out here rather than persisting three
      // separate columns for what's only ever used together as a single
      // connect() call's two arguments.
      final parts = printer.address.split(':');
      final vendorId = int.parse(parts[0]);
      final productId = int.parse(parts[1]);

      final connected = await _plugin.connect(vendorId, productId);
      _stateController.add(
        connected == true
            ? PrinterConnectionState.connected
            : PrinterConnectionState.error,
      );
      if (connected != true) {
        throw DeviceFailure.connectionFailed(
          'Could not connect to ${printer.name}. Confirm the USB cable is '
          'connected and the printer is powered on.',
        );
      }
    } catch (e) {
      _stateController.add(PrinterConnectionState.error);
      rethrow;
    }
  }

  @override
  Future<void> printBytes(Uint8List data) async {
    try {
      await _plugin.write(data);
    } catch (e) {
      throw const DeviceFailure.printFailed(
        'The printer did not accept the print job — check it has paper and '
        'is still connected.',
      );
    }
  }

  @override
  Future<void> disconnect() async {
    // flutter_usb_printer does not expose an explicit disconnect —
    // releasing the USB interface happens on the native side when the
    // connection object is garbage-collected / the app backgrounds.
    // Recorded as a known gap rather than silently assumed equivalent to
    // Bluetooth's explicit disconnect() — a future revision may need a
    // platform-channel addition here if this proves to leak the USB
    // interface in practice on real hardware, which this pass has no
    // way to verify.
    _stateController.add(PrinterConnectionState.disconnected);
  }

  void dispose() {
    _stateController.close();
  }
}
