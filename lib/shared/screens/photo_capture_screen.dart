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
///
/// **Gap-closure pass addendum** (Receipt Photo Attachment on
/// Expenses, this screen's second caller after Product Photo Capture):
/// added a preview step between capture and returning — a shot that's
/// blurry or has glare across the numbers is exactly the failure mode
/// a receipt photo exists to avoid, and there was previously no way to
/// notice that before it was already saved and this screen had already
/// popped. Retake keeps the same live `CameraController` rather than
/// tearing it down and recreating it (`CameraService.capturePhoto` is
/// a plain `controller.takePicture()` — the controller stays valid for
/// another shot afterward), and best-effort deletes the discarded
/// file it's replacing so a string of retakes doesn't leave orphaned
/// photos behind in the documents directory.
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

enum _CaptureState { checking, ready, saving, preview, denied }

class _PhotoCaptureScreenState extends ConsumerState<PhotoCaptureScreen> {
  _CaptureState _state = _CaptureState.checking;
  CameraController? _controller;
  String? _errorMessage;

  /// Set once a shot has been captured and copied to disk, cleared
  /// again on retake — only meaningful while [_state] is
  /// [_CaptureState.preview].
  String? _previewPath;

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
      if (mounted) {
        setState(() {
          _previewPath = destination;
          _state = _CaptureState.preview;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _state = _CaptureState.ready);
        showFulusSnackbar(context, message: "Couldn't save that photo. Please try again.");
      }
    }
  }

  /// Back to a live preview for another shot — the controller from
  /// [_setUp] is still initialized (see this class's own doc comment),
  /// so there's no camera-reinitialization flicker here, just a state
  /// change.
  Future<void> _retake() async {
    final discarded = _previewPath;
    setState(() {
      _previewPath = null;
      _state = _CaptureState.ready;
    });
    if (discarded != null) {
      try {
        await File(discarded).delete();
      } catch (_) {
        // Harmless clutter, not a correctness problem — the user
        // already told us they don't want this shot; failing loudly
        // about cleanup would only confuse them.
      }
    }
  }

  void _confirm() {
    final path = _previewPath;
    if (path != null) Navigator.of(context).pop(path);
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
        _CaptureState.preview => _PreviewBody(path: _previewPath!, onRetake: _retake, onConfirm: _confirm),
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

class _PreviewBody extends StatelessWidget {
  const _PreviewBody({required this.path, required this.onRetake, required this.onConfirm});

  final String path;
  final VoidCallback onRetake;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: Image.file(File(path), fit: BoxFit.contain)),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Expanded(
                child: FulusButton(label: 'Retake', variant: FulusButtonVariant.secondary, onPressed: onRetake),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: FulusButton(label: 'Use photo', onPressed: onConfirm)),
            ],
          ),
        ),
      ],
    );
  }
}
