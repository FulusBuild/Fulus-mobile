import 'dart:async';
import 'dart:typed_data';

import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../../core/errors/failure.dart';
import '../../domain/entities/printer_device.dart';
import '../device_permissions.dart';
import 'receipt_printer.dart';

/// Stage 15 — Device Services (Printing), Bluetooth transport.
///
/// **Built without network/compiler access — a note future-me or
/// another engineer should verify before shipping.** This file was
/// written during an offline design/implementation pass with no way to
/// `flutter pub get`, compile, or run against a real device — see
/// HANDOVER-2.md's own disclosure of this constraint. The
/// print_bluetooth_thermal package's exact current method names/return
/// shapes should be checked against whatever version `flutter pub get`
/// actually resolves before this ships; the architecture below (this
/// class implementing [ReceiptPrinter], everything else in the app
/// depending on that interface rather than this package directly) is
/// deliberately structured so that if a method name here needs
/// adjusting, the fix is contained to this one file.
///
/// Bluetooth Classic SPP (Serial Port Profile) specifically — not BLE.
/// See pubspec.yaml's own comment on why that distinction picked this
/// package over a BLE-oriented one: essentially every budget 58mm/80mm
/// ESC/POS thermal printer sold in this market speaks SPP, appearing to
/// Android as a standard paired Bluetooth device with a serial-style
/// connection, not a BLE peripheral with GATT services.
class BluetoothReceiptPrinter implements ReceiptPrinter {
  BluetoothReceiptPrinter({DevicePermissions? permissions})
      : _permissions = permissions ?? const DevicePermissions();

  final DevicePermissions _permissions;

  final _stateController =
      StreamController<PrinterConnectionState>.broadcast();

  @override
  Stream<PrinterConnectionState> get connectionState => _stateController.stream;

  @override
  Future<void> connect(PairedPrinter printer) async {
    if (printer.transport != PrinterTransport.bluetooth) {
      throw ArgumentError.value(
        printer.transport,
        'printer.transport',
        'BluetoothReceiptPrinter can only connect to a bluetooth-transport '
            'PairedPrinter — the caller (ReceiptPrinterService) is '
            'responsible for dispatching by transport before reaching here.',
      );
    }

    if (!await _permissions.ensureBluetooth()) {
      _stateController.add(PrinterConnectionState.error);
      throw const DeviceFailure.permissionDenied(
        'Bluetooth permission is required to connect to a receipt printer.',
      );
    }

    _stateController.add(PrinterConnectionState.connecting);
    try {
      final connected = await PrintBluetoothThermal.connect(
        macPrinterAddress: printer.address,
      );
      _stateController.add(
        connected ? PrinterConnectionState.connected : PrinterConnectionState.error,
      );
      if (!connected) {
        throw DeviceFailure.connectionFailed(
          'Could not connect to ${printer.name}. Confirm it is powered on '
          'and in range.',
        );
      }
    } catch (e) {
      _stateController.add(PrinterConnectionState.error);
      rethrow;
    }
  }

  @override
  Future<void> printBytes(Uint8List data) async {
    final ok = await PrintBluetoothThermal.writeBytes(data.toList());
    if (!ok) {
      throw const DeviceFailure.printFailed(
        'The printer did not accept the print job — check it has paper and '
        'is still connected.',
      );
    }
  }

  @override
  Future<void> disconnect() async {
    // print_bluetooth_thermal's `disconnect` is a static GETTER
    // (`Future<bool> get disconnect`), not a method — unlike connect()
    // and writeBytes() above, both real methods. This asymmetry in the
    // package's own API is the specific detail most likely to have
    // changed or been misremembered across versions; if this throws a
    // "not a function" / analyzer error, try `PrintBluetoothThermal
    // .disconnect()` instead — see this file's opening note.
    await PrintBluetoothThermal.disconnect;
    _stateController.add(PrinterConnectionState.disconnected);
  }

  void dispose() {
    _stateController.close();
  }
}
