import 'package:camera/camera.dart';

import '../../core/errors/failure.dart';
import '../device_permissions.dart';

/// Stage 15 — Device Services (Camera).
///
/// Camera hardware access as its own device service, separate from
/// [BarcodeScannerService] (scanning/barcode_scanner_service.dart) even
/// though both ultimately open the phone's camera — mobile_scanner owns
/// its own CameraX preview internally for barcode decoding specifically,
/// while this class is for the OTHER camera use cases Stage 15 and the
/// Product Design Bible name: Volume 5 Decision 15's shop-photo visual
/// match capture step (the match/AI logic itself is explicitly out of
/// scope — Decision 15 defers that to Volume 13) and Volume 6 product
/// photos. Two different packages for two different jobs, both real
/// "Camera" per Stage 15's brief, not a duplicate/redundant pair.
///
/// **Built without network/compiler access** — see
/// bluetooth_receipt_printer.dart's own note; camera is the official
/// Flutter-team-maintained plugin, which lowers but doesn't eliminate
/// this pass's inability to verify against a real build.
///
/// Like the other device_services/ classes, this provides pieces for a
/// future screen to assemble (a permission-checked controller, a capture
/// call) — it does not build a camera preview screen itself.
class CameraService {
  CameraService({DevicePermissions? permissions})
      : _permissions = permissions ?? const DevicePermissions();

  final DevicePermissions _permissions;

  Future<void> ensurePermission() async {
    if (!await _permissions.ensureCamera()) {
      throw const DeviceFailure.permissionDenied(
        'Camera permission is required.',
      );
    }
  }

  Future<List<CameraDescription>> availableCameras() {
    return availableCameras_();
  }

  /// Rear camera preferred, falling back to whatever's first if a device
  /// genuinely has no rear-facing camera reported (unusual, but real
  /// budget-device hardware reporting is not something this service
  /// should assume is always well-formed) — Volume 6 product photos and
  /// Decision 15's shop-photo capture are both "point the phone at a
  /// physical thing," never a selfie-style front-camera use case.
  Future<CameraController> createController({
    ResolutionPreset resolution = ResolutionPreset.medium,
  }) async {
    await ensurePermission();
    final cameras = await availableCameras_();
    if (cameras.isEmpty) {
      throw const DeviceFailure.connectionFailed(
        'No camera is available on this device.',
      );
    }
    final rear = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    final controller = CameraController(
      rear,
      resolution,
      enableAudio: false,
    );
    await controller.initialize();
    return controller;
  }

  Future<XFile> capturePhoto(CameraController controller) {
    return controller.takePicture();
  }
}

// Thin, private indirection to the package-level availableCameras()
// function. This is NOT just a testability nicety — it's load-bearing:
// inside CameraService.availableCameras() (the instance method above),
// an unqualified call to `availableCameras()` would resolve to `this
// .availableCameras()` — the instance method itself, per ordinary Dart
// scoping — NOT the package-level function of the same name, even
// though that function is imported into this same file. Written
// naively, that would be infinite self-recursion (a stack overflow at
// runtime, not a compile error, since both are valid zero-argument
// calls). Routing through this separate top-level function — where no
// instance method is in scope to shadow the package's own
// availableCameras() — sidesteps that entirely. It also happens to make
// CameraService.availableCameras() mockable via mocktail the same way
// every other device_services/ class is, which is a genuine secondary
// benefit, just not the reason this indirection exists.
Future<List<CameraDescription>> availableCameras_() => availableCameras();
