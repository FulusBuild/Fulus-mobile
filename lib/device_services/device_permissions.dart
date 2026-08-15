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

  /// Nice-to-have gap closure — Volume 3 Decision 8's other half:
  /// "Each system permission dialog is preceded by one plain-language
  /// line explaining why." That line (`showFulusPermissionPrimer`,
  /// shared/widgets/fulus_dialogs.dart) only belongs on screen when an
  /// OS dialog is actually about to appear — a pure status check, not a
  /// request, so a call site can decide "is there really a dialog
  /// coming?" before deciding whether to show the primer. Checking
  /// first also means a returning owner who already granted the
  /// permission on a previous visit never sees the primer again: [
  /// ensureCamera] would just resolve instantly with no OS dialog of
  /// its own, and a primer with nothing behind it would be a confusing,
  /// unexplained extra dialog rather than a helpful one.
  Future<bool> get hasCameraPermission async => (await Permission.camera.status).isGranted;

  /// Same reasoning as [hasCameraPermission], checking both halves of
  /// the paired request [ensureBluetooth] makes.
  Future<bool> get hasBluetoothPermission async {
    final scan = await Permission.bluetoothScan.status;
    final connect = await Permission.bluetoothConnect.status;
    return scan.isGranted && connect.isGranted;
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
