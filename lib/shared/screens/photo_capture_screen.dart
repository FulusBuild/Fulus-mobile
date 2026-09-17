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

/// Shared photo flow used by products and receipt attachments.
/// A person can take a new photo or choose an existing image from the phone.
/// Selected images are copied into permanent app storage before being returned.
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

enum _CaptureState { checking, ready, saving, preview, unavailable }

class _PhotoCaptureScreenState extends ConsumerState<PhotoCaptureScreen> {
  _CaptureState _state = _CaptureState.checking;
  CameraController? _controller;
  String? _errorMessage;
  String? _previewPath;

  @override
  void initState() {
    super.initState();
    _setUpCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _setUpCamera() async {
    try {
      final controller = await ref.read(cameraServiceProvider).createController();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _state = _CaptureState.ready;
      });
    } on DeviceFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _state = _CaptureState.unavailable;
        _errorMessage = failure.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _state = _CaptureState.unavailable;
        _errorMessage = 'Camera access is unavailable.';
      });
    }
  }

  Future<String> _copyToPermanentStorage(String sourcePath) async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory(p.join(documentsDir.path, 'photos'));
    await photosDir.create(recursive: true);

    final extension = p.extension(sourcePath).isEmpty ? '.jpg' : p.extension(sourcePath);
    final destination = p.join(photosDir.path, '${Ulid()}$extension');
    await File(sourcePath).copy(destination);
    return destination;
  }

  Future<void> _pickFromPhone() async {
    try {
      setState(() => _state = _CaptureState.saving);
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      final sourcePath = result?.files.single.path;
      if (sourcePath == null || sourcePath.isEmpty) {
        if (mounted) setState(() => _state = _CaptureState.ready);
        return;
      }

      final destination = await _copyToPermanentStorage(sourcePath);
      if (!mounted) return;
      setState(() {
        _previewPath = destination;
        _state = _CaptureState.preview;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _CaptureState.ready);
      showFulusSnackbar(context, message: "Couldn't choose that image. Please try again.");
    }
  }

  Future<void> _takePhoto() async {
    final controller = _controller;
    if (controller == null) return;

    setState(() => _state = _CaptureState.saving);
    try {
      final captured = await ref.read(cameraServiceProvider).capturePhoto(controller);
      final destination = await _copyToPermanentStorage(captured.path);
      if (!mounted) return;
      setState(() {
        _previewPath = destination;
        _state = _CaptureState.preview;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _CaptureState.ready);
      showFulusSnackbar(context, message: "Couldn't save that photo. Please try again.");
    }
  }

  Future<void> _chooseAgain() async {
    final oldPath = _previewPath;
    setState(() {
      _previewPath = null;
      _state = _CaptureState.ready;
    });
    if (oldPath != null) {
      try {
        await File(oldPath).delete();
      } catch (_) {}
    }
  }

  void _usePhoto() {
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
        _CaptureState.checking => const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        _CaptureState.unavailable => _UnavailableBody(
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
                              onPressed: _takePhoto,
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
            onChooseAgain: _chooseAgain,
            onUse: _usePhoto,
          ),
      },
    );
  }
}

class _UnavailableBody extends StatelessWidget {
  const _UnavailableBody({required this.message, required this.onPick, required this.onSkip});

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
            const Icon(FulusIcons.image, color: Colors.white, size: 48),
            const SizedBox(height: AppSpacing.md),
            Text(message, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.lg),
            FulusButton(label: 'Choose from phone', icon: FulusIcons.image, onPressed: onPick),
            const SizedBox(height: AppSpacing.sm),
            FulusButton(label: 'Skip for now', variant: FulusButtonVariant.text, onPressed: onSkip),
          ],
        ),
      ),
    );
  }
}

class _PreviewBody extends StatelessWidget {
  const _PreviewBody({required this.path, required this.onChooseAgain, required this.onUse});

  final String path;
  final VoidCallback onChooseAgain;
  final VoidCallback onUse;

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
                  onPressed: onChooseAgain,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: FulusButton(label: 'Use photo', onPressed: onUse)),
            ],
          ),
        ),
      ],
    );
  }
}
