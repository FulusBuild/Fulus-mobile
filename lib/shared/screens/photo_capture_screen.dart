import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:ulid/ulid.dart';

import '../../app/providers.dart';
import '../../core/errors/failure.dart';
import '../../core/theme/design_tokens.dart';
import '../widgets/widgets.dart';

/// Gap fix — Volume 6 product photos: `Product.photoPath` and
/// `ProductRepository.updateProduct(photoPath: ...)` already existed
/// fully wired; `CameraService` (device_services/camera/) already
/// existed too. Nothing anywhere called either. This screen is that
/// missing caller — shared, not Product-specific, matching
/// BarcodeScanScreen's own "one screen, multiple callers" shape.
///
/// The captured `XFile` gets copied into the app's own permanent
/// documents directory before this screen returns a path — `XFile`'s
/// own path can be a transient cache location depending on platform,
/// and `Product.photoPath`'s own doc comment says "a local file path,"
/// implying something this device can keep relying on, not a path that
/// might be cleaned up by the OS the way a cache directory can be.
class PhotoCaptureScreen extends ConsumerStatefulWidget {
  const PhotoCaptureScreen({super.key, this.title = 'Take a photo'});

  final String title;

  static Future<String?> capture(BuildContext context, {String title = 'Take a photo'}) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => PhotoCaptureScreen(title: title)),
    );
  }

  @override
  ConsumerState<PhotoCaptureScreen> createState() => _PhotoCaptureScreenState();
}

enum _CaptureState { checking, ready, denied, saving }

class _PhotoCaptureScreenState extends ConsumerState<PhotoCaptureScreen> {
  _CaptureState _state = _CaptureState.checking;
  CameraController? _controller;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _setUp();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _setUp() async {
    final service = ref.read(cameraServiceProvider);
    try {
      final controller = await service.createController();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _state = _CaptureState.ready;
      });
    } on DeviceFailure catch (f) {
      // DeviceFailure's concrete variants (_PermissionDenied,
      // _ConnectionFailed, etc.) are private to failure.dart — callers
      // outside that file can't `is`-check or pattern-match which one
      // this is, only read its message. So this shows that message
      // directly instead of trying to pick between two prewritten
      // strings for a distinction this file can't actually see.
      if (!mounted) return;
      setState(() {
        _state = _CaptureState.denied;
        _errorMessage = f.message;
      });
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null) return;
    setState(() => _state = _CaptureState.saving);
    try {
      final service = ref.read(cameraServiceProvider);
      final captured = await service.capturePhoto(controller);
      final documentsDir = await getApplicationDocumentsDirectory();
      final photosDir = Directory(p.join(documentsDir.path, 'photos'));
      if (!await photosDir.exists()) {
        await photosDir.create(recursive: true);
      }
      final destination = p.join(photosDir.path, '${Ulid()}${p.extension(captured.path)}');
      await File(captured.path).copy(destination);
      if (mounted) Navigator.of(context).pop(destination);
    } catch (_) {
      if (mounted) {
        setState(() => _state = _CaptureState.ready);
        showFulusSnackbar(context, message: "Couldn't save that photo. Please try again.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(widget.title), backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: switch (_state) {
        _CaptureState.checking => const Center(child: CircularProgressIndicator(color: Colors.white)),
        _CaptureState.denied => _MessageBody(
            icon: Icons.camera_alt_outlined,
            message: _errorMessage ?? 'Camera access needed to take a photo.',
            onSkip: () => Navigator.of(context).pop(),
          ),
        _CaptureState.ready || _CaptureState.saving => Stack(
            fit: StackFit.expand,
            children: [
              if (_controller != null) CameraPreview(_controller!),
              Positioned(
                bottom: AppSpacing.xl,
                left: 0,
                right: 0,
                child: Center(
                  child: _state == _CaptureState.saving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : FloatingActionButton(onPressed: _capture, child: const Icon(Icons.camera_alt)),
                ),
              ),
            ],
          ),
      },
    );
  }
}

class _MessageBody extends StatelessWidget {
  const _MessageBody({required this.icon, required this.message, required this.onSkip});
  final IconData icon;
  final String message;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 48),
            const SizedBox(height: AppSpacing.md),
            Text(message, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.lg),
            FulusButton(label: 'Skip for now', onPressed: onSkip),
          ],
        ),
      ),
    );
  }
}
