import 'dart:io';

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:ulid/ulid.dart';

import '../../core/theme/design_tokens.dart';
import '../widgets/widgets.dart';

enum _CaptureState { checking, ready, saving, preview, unavailable }

class PhotoCaptureScreen extends ConsumerStatefulWidget {
  const PhotoCaptureScreen({super.key});

  static Future<String?> capture(BuildContext context) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const PhotoCaptureScreen()),
    );
  }

  @override
  ConsumerState<PhotoCaptureScreen> createState() => _PhotoCaptureScreenState();
}

class _PhotoCaptureScreenState extends ConsumerState<PhotoCaptureScreen> {
  CameraController? _controller;
  _CaptureState _state = _CaptureState.checking;
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
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _state = _CaptureState.unavailable);
        return;
      }
      final controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _state = _CaptureState.ready;
      });
    } catch (_) {
      if (mounted) setState(() => _state = _CaptureState.unavailable);
    }
  }

  Future<String> _copyToPermanentStorage(String sourcePath) async {
    final root = await getApplicationDocumentsDirectory();
    final photosDir = Directory(p.join(root.path, 'photos'));
    await photosDir.create(recursive: true);
    final extension = p.extension(sourcePath).isEmpty ? '.jpg' : p.extension(sourcePath);
    final destination = p.join(photosDir.path, '${Ulid()}$extension');
    await File(sourcePath).copy(destination);
    return destination;
  }

  Future<void> _pickFromPhone() async {
    try {
      setState(() => _state = _CaptureState.saving);
      final files = await FilePicker.pickFiles(type: FileType.image);
      if (files.isEmpty) {
        if (mounted) {
          setState(() => _state = _controller?.value.isInitialized == true
              ? _CaptureState.ready
              : _CaptureState.unavailable);
        }
        return;
      }

      final sourcePath = files.first.path;
      if (sourcePath == null || sourcePath.isEmpty) {
        if (mounted) setState(() => _state = _CaptureState.unavailable);
        return;
      }

      final destination = await _copyToPermanentStorage(sourcePath);
      if (!mounted) return;
      setState(() {
        _previewPath = destination;
        _state = _CaptureState.preview;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _state = _controller?.value.isInitialized == true
            ? _CaptureState.ready
            : _CaptureState.unavailable);
      }
    }
  }

  Future<void> _takePhoto() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || controller.value.isTakingPicture) {
      return;
    }
    try {
      setState(() => _state = _CaptureState.saving);
      final photo = await controller.takePicture();
      final destination = await _copyToPermanentStorage(photo.path);
      if (!mounted) return;
      setState(() {
        _previewPath = destination;
        _state = _CaptureState.preview;
      });
    } catch (_) {
      if (mounted) setState(() => _state = _CaptureState.ready);
    }
  }

  Future<void> _chooseAgain() async {
    final oldPath = _previewPath;
    setState(() {
      _previewPath = null;
      _state = _controller?.value.isInitialized == true
          ? _CaptureState.ready
          : _CaptureState.unavailable;
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
    return FulusScreen(
      title: 'Product photo',
      subtitle: 'Take a photo or choose an image from your phone',
      onBack: () => Navigator.of(context).pop(),
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_state == _CaptureState.checking || _state == _CaptureState.saving) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_state == _CaptureState.preview && _previewPath != null) {
      return Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Image.file(File(_previewPath!), fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: FulusButton(
                  label: 'Choose again',
                  icon: FulusIcons.image,
                  variant: FulusButtonVariant.secondary,
                  onPressed: _chooseAgain,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: FulusButton(
                  label: 'Use photo',
                  icon: FulusIcons.check,
                  onPressed: _usePhoto,
                ),
              ),
            ],
          ),
        ],
      );
    }

    if (_state == _CaptureState.unavailable) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(FulusIcons.camera, size: 48, color: AppColors.mutedOf(context)),
            const SizedBox(height: AppSpacing.md),
            const Text('Camera is unavailable on this device.'),
            const SizedBox(height: AppSpacing.lg),
            FulusButton(
              label: 'Choose from phone',
              icon: FulusIcons.image,
              variant: FulusButtonVariant.secondary,
              onPressed: _pickFromPhone,
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: CameraPreview(_controller!),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: AppSpacing.lg,
          child: Center(
            child: FulusButton(
              label: 'Choose from phone',
              icon: FulusIcons.image,
              variant: FulusButtonVariant.secondary,
              onPressed: _pickFromPhone,
            ),
          ),
        ),
        Positioned(
          right: AppSpacing.lg,
          bottom: AppSpacing.lg,
          child: FloatingActionButton(
            onPressed: _takePhoto,
            tooltip: 'Take photo',
            child: const Icon(FulusIcons.camera),
          ),
        ),
      ],
    );
  }
}
