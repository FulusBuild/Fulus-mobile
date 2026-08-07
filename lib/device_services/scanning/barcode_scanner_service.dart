import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/errors/failure.dart';
import '../device_permissions.dart';

/// One decoded barcode — deliberately just the raw value. Volume 5
/// ("Finding Products"): a scanned barcode is matched against
/// Product.barcode/sku by whichever future Sell screen (Stage 7, not
/// this stage) owns that lookup; this service's job ends at "here is
/// the string the camera read," not resolving it to a product itself —
/// ProductRepository already exists and already owns that query.
class BarcodeScanResult extends Equatable {
  const BarcodeScanResult({required this.rawValue});

  final String rawValue;

  @override
  List<Object?> get props => [rawValue];
}

/// Stage 15 — Device Services (Scanning).
///
/// **Built without network/compiler access** — mobile_scanner's exact
/// current API should be checked against whatever version `flutter pub
/// get` resolves; see bluetooth_receipt_printer.dart's own note on this
/// same constraint applying throughout this pass. mobile_scanner is
/// specifically chosen (over hand-rolling ML Kit via a platform channel)
/// because it is the Flutter community's standard, actively-referenced
/// choice for this exact job — barcode decoding is a nontrivial thing to
/// get right, unlike raw camera frame capture.
///
/// This class does not build UI (no screens exist yet for ANY feature in
/// this codebase — see HANDOVER-2.md). It provides the pieces a future
/// scan screen assembles: a correctly-configured controller, the
/// raw-camera-frame -&gt; BarcodeScanResult mapping, and the
/// vibration+sound confirmation Volume 5 specifies ("confirmed with a
/// short vibration and sound so a fast-moving cashier doesn't have to
/// watch the screen").
class BarcodeScannerService {
  BarcodeScannerService({DevicePermissions? permissions})
      : _permissions = permissions ?? const DevicePermissions();

  final DevicePermissions _permissions;

  /// Volume 3 Decision 8 ("Permissions, Requested Contextually") means
  /// this is called by the future scan screen right before it builds a
  /// MobileScanner widget, never earlier — this service has no
  /// opinion on when that is, only on what to do when asked.
  Future<void> ensurePermission() async {
    if (!await _permissions.ensureCamera()) {
      throw const DeviceFailure.permissionDenied(
        'Camera permission is required to scan a barcode.',
      );
    }
  }

  /// Sensible defaults for a POS barcode-lookup use case specifically —
  /// NOT a general-purpose camera/scan configuration. `formats` is left
  /// at mobile_scanner's own default (all supported formats) deliberately:
  /// restricting to e.g. only EAN-13 would silently fail on a real
  /// product whose barcode happens to be Code-128 or UPC-A, and this
  /// service has no reliable way to know in advance which formats a
  /// given shop's inventory actually uses.
  MobileScannerController createController() {
    return MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
  }

  /// Takes the first decodable barcode in a capture — a capture can
  /// contain several when multiple codes are visible in frame at once,
  /// and Volume 5's flow (scan one product at a time, into a cart) has
  /// no use for more than the first successfully-read one per capture
  /// event.
  BarcodeScanResult? extractResult(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.isNotEmpty) {
        return BarcodeScanResult(rawValue: value);
      }
    }
    return null;
  }

  /// Volume 5's exact feedback pairing. Uses Flutter's own
  /// HapticFeedback/SystemSound (package:flutter/services.dart) rather
  /// than a dedicated vibration package — both are already part of the
  /// Flutter SDK, need no new pubspec dependency, and are sufficient for
  /// "short vibration and sound," which doesn't call for the finer
  /// vibration-pattern control a dedicated package would add.
  void confirmScan() {
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);
  }
}
