import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Largest object the `product-images` bucket accepts (see the storage
/// migration). Anything still above this after compression can never upload.
const int kMaxProductImageBytes = 5 * 1024 * 1024;

class _CompressRequest {
  const _CompressRequest(this.bytes, this.maxDimension, this.quality);
  final Uint8List bytes;
  final int maxDimension;
  final int quality;
}

Uint8List? _compressBytes(_CompressRequest request) {
  final decoded = img.decodeImage(request.bytes);
  if (decoded == null) return null;
  var image = img.bakeOrientation(decoded);
  final longest = image.width > image.height ? image.width : image.height;
  if (longest > request.maxDimension) {
    image = image.width >= image.height
        ? img.copyResize(image, width: request.maxDimension)
        : img.copyResize(image, height: request.maxDimension);
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: request.quality));
}

/// Downscales and re-encodes [source] as JPEG when that makes it smaller.
///
/// Returns [source] unchanged when it cannot be decoded or compression does
/// not help, so callers can always use the result. The source is deliberately
/// preserved until the upload and cloud URL update have succeeded. Transparent
/// PNGs lose their alpha channel (catalog photos are photographs, not artwork).
/// Decoding runs on a background isolate.
Future<File> compressImageFile(
  File source, {
  int maxDimension = 1600,
  int quality = 82,
}) async {
  try {
    final original = await source.readAsBytes();
    final compressed = await compute(
      _compressBytes,
      _CompressRequest(original, maxDimension, quality),
    );
    if (compressed == null ||
        compressed.isEmpty ||
        compressed.length >= original.length) {
      return source;
    }
    final target = File('${p.withoutExtension(source.path)}.optimized.jpg');
    final temp = File('${target.path}.tmp');
    await temp.writeAsBytes(compressed, flush: true);
    await temp.rename(target.path);
    return target;
  } catch (_) {
    return source;
  }
}

