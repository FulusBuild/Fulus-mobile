import 'package:permission_handler/permission_handler.dart';

/// Stage 15 — Device Services.
///
/// One small helper, shared by every device service in this directory,
/// rather than each of printing/scanning/camera hand-rolling its own
/// permission_handler calls. Volume 3 Decision 8 ("Permissions,
/// Requested Contextually... never upfront") governs WHEN each of these
/// is called — always lazily, the moment a specific feature is actually
/// used (a "Pair a printer" tap, opening the barcode scanner, opening
/// the camera) — never from bootstrap.dart or app startup. This class
/// only provides the mechanism; every call site elsewhere in
/// device_services/ owns its own "ask right before I need it" timing.
class DevicePermissions {
  const DevicePermissions();

  /// Bluetooth pairing/discovery for receipt printers. Requests BOTH
  /// scan and connect together, deliberately — Android 12+ treats them
  /// as separate grants, but this app has no scenario where it wants one
  /// without the other (printer discovery always leads straight into
  /// connecting to whichever device is chosen), so asking twice in
  /// quick succession would just be two prompts for what the user
  /// experiences as one decision ("let this app use Bluetooth").
  Future<bool> ensureBluetooth() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    return statuses.values.every((s) => s.isGranted);
  }

  Future<bool> ensureCamera() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  /// USB host-mode access is deliberately NOT requested through
  /// permission_handler here — on Android, attaching to a specific USB
  /// device is authorized through a per-device system dialog
  /// (UsbManager.requestPermission, triggered natively) rather than a
  /// permission_handler-style app permission, and flutter_usb_printer
  /// owns that native call itself when a specific device is opened. See
  /// printing/usb_receipt_printer.dart's own doc comment on this exact
  /// split.
}
