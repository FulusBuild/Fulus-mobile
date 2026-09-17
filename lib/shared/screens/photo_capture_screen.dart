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
  const PhotoCaptureScreen({super.key, this.title = 'Product photo'});

  final String title;

  static Future<String?> capture(BuildContext context, {String title = 'Product photo'}) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => PhotoCaptureScreen(title: title)),
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
      final controller = CameraController(cameras.first, ResolutionPreset.high, enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      setState(() => _state = _CaptureState.ready);
    } catch (_) {
      if (mounted) setState(() => _state = _CaptureState.unavailable);
    }
  }

  Future<String?> _copyToPermanentStorage(String sourcePath) async {
    setState(() => _state = _CaptureState.saving);
    try {
      final directory = await getApplicationDocumentsDirectory();
      final photosDirectory = Directory(p.join(directory.path, 'photos'));
      await photosDirectory.create(recursive: true);
      final extension = p.extension(sourcePath).isEmpty ? '.jpg' : p.extension(sourcePath);
      final destinationPath = p.join(photosDirectory.path, '${Ulid().toUuid()}$extension');
      await File(sourcePath).copy(destinationPath);
      if (!mounted) return destinationPath;
      setState(() {
        _previewPath = destinationPath;
        _state = _CaptureState.preview;
      });
      return destinationPath;
    } catch (_) {
      if (mounted) setState(() => _state = _CaptureState.ready);
      return null;
    }
  }

  Future<void> _pickFromPhone() async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.image);
      if (files.isEmpty) return;
      final sourcePath = files.first.path;
      if (sourcePath == null || sourcePath.isEmpty) return;
      await _copyToPermanentStorage(sourcePath);
    } catch (_) {
      if (mounted) setState(() => _state = _CaptureState.ready);
    }
  }

  Future<void> _takePhoto() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || controller.value.isTakingPicture) return;
    try {
      final image = await controller.takePicture();
      await _copyToPermanentStorage(image.path);
    } catch (_) {
      if (mounted) setState(() => _state = _CaptureState.ready);
    }
  }

  Future<void> _chooseAgain() async {
    final oldPath = _previewPath;
    setState(() {
      _previewPath = null;
      _state = _controller?.value.isInitialized == true ? _CaptureState.ready : _CaptureState.unavailable;
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
      title: widget.title,
      subtitle: 'Take a photo or choose an image from your phone',
      body: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_state == _CaptureState.checking || _state == _CaptureState.saving) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_state == _CaptureState.preview && _previewPath != null) {
      return _buildPreview(context);
    }

    if (_state == _CaptureState.unavailable) {
      return _buildUnavailable(context);
    }

    return _buildCamera(context);
  }

  Widget _buildCamera(BuildContext context) {
    final controller = _controller;
    return Column(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: controller != null && controller.value.isInitialized
                ? CameraPreview(controller)
                : const SizedBox.shrink(),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: FulusButton(
                label: 'Choose from phone',
                icon: FulusIcons.image,
                variant: FulusButtonVariant.secondary,
                onPressed: _pickFromPhone,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: FulusButton(
                label: 'Take photo',
                icon: FulusIcons.camera,
                onPressed: _takePhoto,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildUnavailable(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(FulusIcons.camera, size: 48, color: AppColors.textSecondaryOf(context)),
            const SizedBox(height: AppSpacing.md),
            Text('Camera unavailable', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'You can still choose an existing image from your phone.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondaryOf(context)),
            ),
            const SizedBox(height: AppSpacing.lg),
            FulusButton(
              label: 'Choose from phone',
              icon: FulusIcons.image,
              onPressed: _pickFromPhone,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(BuildContext context) {
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
}
