import 'package:flutter_usb_printer/flutter_usb_printer.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../../core/errors/failure.dart';
import '../../domain/entities/printer_device.dart';
import '../device_permissions.dart';

/// Stage 15 — Device Services (Printing).
///
/// Volume 11's "Pairing" step needs a list of candidate devices to
/// choose from before PrinterRepository.pair (data layer) ever gets
/// called — this class is that list, for both transports. Deliberately
/// separate from PrinterRepository: this returns transient
/// [PrinterDevice]s from a live hardware scan, never persisted rows —
/// PrinterRepository only enters once an owner has actually picked one.
class PrinterDiscoveryService {
  PrinterDiscoveryService({DevicePermissions? permissions})
      : _permissions = permissions ?? const DevicePermissions();

  final DevicePermissions _permissions;

  /// Already-PAIRED-at-the-OS-level Bluetooth devices, per
  /// print_bluetooth_thermal's own model (it lists the phone's existing
  /// Bluetooth pairings, the same list Android's own Bluetooth settings
  /// screen shows, rather than performing a fresh discovery scan) —
  /// matching Volume 11 Decision 39's framing that this app's own
  /// "pairing" step is really just picking which of the phone's already-
  /// Bluetooth-paired devices is the receipt printer, not a from-scratch
  /// Bluetooth discovery UI. An owner whose printer isn't in this list
  /// yet needs to pair it via Android's own Bluetooth settings first —
  /// a real, honest limitation of Bluetooth Classic (unlike BLE, SPP
  /// devices generally must be OS-paired before an app can open a
  /// socket to them at all), not a gap in this method.
  Future<List<PrinterDevice>> scanBluetooth() async {
    if (!await _permissions.ensureBluetooth()) {
      throw const DeviceFailure.permissionDenied(
        'Bluetooth permission is required to find receipt printers.',
      );
    }

    final paired = await PrintBluetoothThermal.pairedBluetooths;
    return paired
        .map(
          (device) => PrinterDevice(
            name: device.name,
            // `macAdress` — missing the second "d" — is not a typo
            // introduced here; it's the actual field name on
            // print_bluetooth_thermal's own BluetoothInfo class. Do not
            // "fix" this to `macAddress` without first confirming the
            // installed package version still spells it this way, or
            // this line will fail to compile.
            address: device.macAdress,
            transport: PrinterTransport.bluetooth,
          ),
        )
        .toList();
  }

  /// Currently-attached USB devices — no separate permission gate here;
  /// see usb_receipt_printer.dart's own doc comment on why USB
  /// authorization happens per-device, natively, at connect time
  /// instead.
  ///
  /// Every attached USB device is listed here, not just ones this app
  /// can already confirm are printers — Android's UsbManager has no
  /// reliable, generic "this is a printer" signal for arbitrary vendor
  /// hardware, so filtering by device CLASS would risk silently hiding
  /// a real printer whose firmware doesn't report the class byte this
  /// app happened to check for. An owner picking the wrong device from
  /// this list fails harmlessly at the connect/test-print step instead.
  Future<List<PrinterDevice>> scanUsb() async {
    final devices = await FlutterUsbPrinter.getUSBDeviceList();
    return devices.map((device) {
      return PrinterDevice(
        name: device['productName'] as String? ?? 'USB printer',
        // See usb_receipt_printer.dart's own comment on why address is
        // "vendorId:productId" — the two arguments FlutterUsbPrinter's
        // own connect() call actually needs, and nothing else about a
        // USB device is stable/meaningful to persist here.
        address: '${device['vendorId']}:${device['productId']}',
        transport: PrinterTransport.usb,
      );
    }).toList();
  }
}
