import 'dart:io';

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:ulid/ulid.dart';

import '../../app/providers.dart';
import '../../core/errors/failure.dart';
import '../../core/theme/design_tokens.dart';
import '../widgets/widgets.dart';

/// Shared product/receipt photo flow. A person can either take a new photo
/// with the camera or choose an existing image from the phone. Both paths
/// copy the selected image into the app's permanent documents directory so
/// Product.photoPath / receipt attachments never depend on a transient
/// picker or camera cache path.
///
/// The captured/selected image gets a preview step before this screen returns.
/// Retake/choose again keeps the existing flow simple and lets a person check
/// that the product image is actually the one they intended to use.
class PhotoCaptureScreen extends ConsumerStatefulWidget {
  const PhotoCaptureScreen({super.key, this.title = 'Add a photo'});

  final String title;

  static Future<String?> capture(BuildContext context, {String title = 'Add a photo'}) {
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
      if (!mounted) return;
      setState(() {
        _state = _CaptureState.denied;
        _errorMessage = f.message;
      });
    }
  }

  Future<String?> _copyToPermanentStorage(String sourcePath) async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory(p.join(documentsDir.path, 'photos'));
    if (!await photosDir.exists()) {
      await photosDir.create(recursive: true);
    }
    final extension = p.extension(sourcePath).isEmpty ? '.jpg' : p.extension(sourcePath);
    final destination = p.join(photosDir.path, '${Ulid()}$extension');
    await File(sourcePath).copy(destination);
    return destination;
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null) return;
    setState(() => _state = _CaptureState.saving);
    try {
      final service = ref.read(cameraServiceProvider);
      final captured = await service.capturePhoto(controller);
      final destination = await _copyToPermanentStorage(captured.path);
      if (!mounted) return;
      setState(() {
        _previewPath = destination;
        _state = _CaptureState.preview;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _state = _CaptureState.ready);
        showFulusSnackbar(context, message: "Couldn't save that photo. Please try again.");
      }
    }
  }

  Future<void> _pickFromPhone() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      final sourcePath = result?.files.single.path;
      if (sourcePath == null || sourcePath.isEmpty) return;

      if (mounted) setState(() => _state = _CaptureState.saving);
      final destination = await _copyToPermanentStorage(sourcePath);
      if (!mounted) return;
      setState(() {
        _previewPath = destination;
        _state = _CaptureState.preview;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _state = _CaptureState.ready);
        showFulusSnackbar(context, message: "Couldn't choose that image. Please try again.");
      }
    }
  }

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
        // Best-effort cleanup only; the chosen replacement remains usable.
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
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: switch (_state) {
        _CaptureState.checking => const Center(child: CircularProgressIndicator(color: Colors.white)),
        _CaptureState.denied => _MessageBody(
            icon: FulusIcons.camera,
            message: _errorMessage ?? 'Camera access is unavailable.',
            onPick: _pickFromPhone,
            onSkip: () => Navigator.of(context).pop(),
          ),
        _CaptureState.ready || _CaptureState.saving => Stack(
            fit: StackFit.expand,
            children: [
              if (_controller != null) CameraPreview(_controller!),
              Positioned(
                left: AppSpacing.lg,
                right: AppSpacing.lg,
                bottom: AppSpacing.xl,
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: FulusButton(
                          label: 'Choose from phone',
                          icon: FulusIcons.image,
                          variant: FulusButtonVariant.secondary,
                          onPressed: _state == _CaptureState.saving ? null : _pickFromPhone,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _state == _CaptureState.saving
                          ? const SizedBox(
                              height: 56,
                              child: Center(child: CircularProgressIndicator(color: Colors.white)),
                            )
                          : FloatingActionButton(
                              onPressed: _capture,
                              tooltip: 'Take photo',
                              child: const Icon(FulusIcons.camera),
                            ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        _CaptureState.preview => _PreviewBody(
            path: _previewPath!,
            onRetake: _retake,
            onConfirm: _confirm,
          ),
      },
    );
  }
}

class _MessageBody extends StatelessWidget {
  const _MessageBody({
    required this.icon,
    required this.message,
    required this.onPick,
    required this.onSkip,
  });

  final IconData icon;
  final String message;
  final VoidCallback onPick;
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
            FulusButton(
              label: 'Choose from phone',
              icon: FulusIcons.image,
              onPressed: onPick,
            ),
            const SizedBox(height: AppSpacing.sm),
            FulusButton(
              label: 'Skip for now',
              variant: FulusButtonVariant.text,
              onPressed: onSkip,
            ),
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
                child: FulusButton(
                  label: 'Choose again',
                  variant: FulusButtonVariant.secondary,
                  onPressed: onRetake,
                ),
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
