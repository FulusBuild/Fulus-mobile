import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/providers.dart';
import '../../core/errors/failure.dart';
import '../../core/theme/design_tokens.dart';
import '../widgets/widgets.dart';

/// Gap fix: BarcodeScannerService (device_services/scanning/) was fully
/// built — permission handling, a configured controller, the
/// vibration+sound confirmation Volume 5 specifies — with no screen
/// anywhere in the app that ever used it (confirmed by grep: no
/// reference to it outside app/providers.dart and app/bootstrap.dart).
/// This is that missing screen, shared between Sell (find a product to
/// sell) and Add/Edit Product (fill the barcode field) rather than
/// building two near-identical camera screens.
///
/// Manual entry is always available, not just after a permission
/// denial — Volume 12/Production Rules: "manual entry fallback always
/// available" for camera-unavailable states in general, which a
/// scratched or damaged barcode qualifies as just as much as a denied
/// permission does.
class BarcodeScanScreen extends ConsumerStatefulWidget {
  const BarcodeScanScreen({super.key, this.title = 'Scan a barcode'});

  final String title;

  /// Pushes this screen and returns the scanned (or manually entered)
  /// value, or null if the user backed out without one.
  static Future<String?> scan(BuildContext context, {String title = 'Scan a barcode'}) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => BarcodeScanScreen(title: title)),
    );
  }

  @override
  ConsumerState<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

enum _PermissionState { checking, granted, denied }

class _BarcodeScanScreenState extends ConsumerState<BarcodeScanScreen> {
  _PermissionState _permission = _PermissionState.checking;
  MobileScannerController? _controller;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _checkPermission() async {
    final service = ref.read(barcodeScannerServiceProvider);
    try {
      await service.ensurePermission();
      if (!mounted) return;
      setState(() {
        _controller = service.createController();
        _permission = _PermissionState.granted;
      });
    } on DeviceFailure {
      if (mounted) setState(() => _permission = _PermissionState.denied);
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final service = ref.read(barcodeScannerServiceProvider);
    final result = service.extractResult(capture);
    if (result == null) return;
    _handled = true;
    service.confirmScan();
    Navigator.of(context).pop(result.rawValue);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.keyboard_outlined),
            tooltip: 'Enter manually',
            onPressed: _enterManually,
          ),
        ],
      ),
      body: switch (_permission) {
        _PermissionState.checking => const Center(child: CircularProgressIndicator(color: Colors.white)),
        _PermissionState.denied => _PermissionDeniedBody(onEnterManually: _enterManually),
        _PermissionState.granted => Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(controller: _controller, onDetect: _onDetect),
              // A simple viewfinder frame — mobile_scanner draws no
              // overlay of its own by default.
              Center(
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                ),
              ),
            ],
          ),
      },
    );
  }

  Future<void> _enterManually() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enter barcode'),
        content: FulusTextField(label: 'Barcode', controller: controller, keyboardType: TextInputType.text),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FulusButton(
            label: 'Use this',
            onPressed: () {
              final text = controller.text.trim();
              Navigator.of(dialogContext).pop(text.isEmpty ? null : text);
            },
          ),
        ],
      ),
    );
    if (value != null && mounted) Navigator.of(context).pop(value);
  }
}

class _PermissionDeniedBody extends StatelessWidget {
  const _PermissionDeniedBody({required this.onEnterManually});
  final VoidCallback onEnterManually;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 48),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Camera access needed to scan',
              style: AppTypography.heading.copyWith(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'You can also type the barcode in by hand.',
              style: TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            FulusButton(label: 'Enter barcode manually', onPressed: onEnterManually),
          ],
        ),
      ),
    );
  }
}
