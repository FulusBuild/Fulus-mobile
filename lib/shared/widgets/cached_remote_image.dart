import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Disk cache for cloud product photos.
///
/// Photo URLs are immutable (each upload gets a new object name), so a cached
/// file never goes stale. Files are kept in the app support directory, which
/// the OS does not purge like the temp directory.
class RemoteImageDiskCache {
  RemoteImageDiskCache._();

  static final RemoteImageDiskCache instance = RemoteImageDiskCache._();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  final Map<String, Future<File?>> _inFlight = {};
  Directory? _directory;

  static const int _maxCacheBytes = 100 * 1024 * 1024;
  static const int _maxCachedFileBytes = 10 * 1024 * 1024;

  Future<Directory> _cacheDirectory() async {
    final existing = _directory;
    if (existing != null) return existing;
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'image_cache'));
    await dir.create(recursive: true);
    return _directory = dir;
  }

  Future<File> _fileFor(String url) async {
    final dir = await _cacheDirectory();
    return File(p.join(dir.path, sha1.convert(utf8.encode(url)).toString()));
  }

  /// The cached file for [url], or null when it has not been downloaded.
  Future<File?> cachedFile(String url) async {
    try {
      final file = await _fileFor(url);
      if (await file.exists() && await file.length() > 0) {
        await file.setLastModified(DateTime.now());
        return file;
      }
    } catch (_) {}
    return null;
  }

  /// Downloads [url] into the cache (once, even if requested concurrently).
  /// Returns null on any failure; callers fall back to the network image.
  Future<File?> prefetch(String url) {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return Future.value(null);
    }
    return _inFlight.putIfAbsent(
      url,
      () => _download(url).whenComplete(() => _inFlight.remove(url)),
    );
  }

  Future<void> _enforceCacheLimit({required String protectedPath}) async {
    try {
      final dir = await _cacheDirectory();
      final files = <File>[];
      await for (final entry in dir.list(followLinks: false)) {
        if (entry is File && !entry.path.endsWith('.tmp')) files.add(entry);
      }
      final sized = <({File file, int bytes, DateTime modified})>[];
      var total = 0;
      for (final file in files) {
        final stat = await file.stat();
        total += stat.size;
        sized.add((file: file, bytes: stat.size, modified: stat.modified));
      }
      sized.sort((a, b) => a.modified.compareTo(b.modified));
      for (final item in sized) {
        if (total <= _maxCacheBytes) break;
        if (item.file.path == protectedPath) continue;
        try {
          await item.file.delete();
          total -= item.bytes;
        } catch (_) {
          // Cache eviction is best-effort; a later write can retry it.
        }
      }
    } catch (_) {
      // A cache maintenance failure must never break product rendering or sync.
    }
  }

  Future<File?> _download(String url) async {
    try {
      final cached = await cachedFile(url);
      if (cached != null) return cached;
      final response = await _dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      final contentType = response.headers.value(Headers.contentTypeHeader) ?? '';
      if (response.statusCode != 200 ||
          bytes == null ||
          bytes.isEmpty ||
          bytes.length > _maxCachedFileBytes ||
          (contentType.isNotEmpty && !contentType.startsWith('image/'))) {
        return null;
      }
      final file = await _fileFor(url);
      final temp = File('${file.path}.tmp');
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
      await _enforceCacheLimit(protectedPath: file.path);
      return file;
    } catch (_) {
      return null;
    }
  }
}

/// Drop-in replacement for `Image.network` that serves from the disk cache
/// when possible and fills the cache otherwise.
class CachedRemoteImage extends StatefulWidget {
  const CachedRemoteImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.errorBuilder,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  State<CachedRemoteImage> createState() => _CachedRemoteImageState();
}

class _CachedRemoteImageState extends State<CachedRemoteImage> {
  File? _cached;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    unawaited(_resolve());
  }

  @override
  void didUpdateWidget(CachedRemoteImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _cached = null;
      _resolved = false;
      unawaited(_resolve());
    }
  }

  Future<void> _resolve() async {
    final url = widget.url;
    final file = await RemoteImageDiskCache.instance.cachedFile(url);
    if (!mounted || url != widget.url) return;
    setState(() {
      _cached = file;
      _resolved = true;
    });
    if (file == null) {
      // Not cached yet: the network image below paints now; this stores a copy
      // so the next view (including offline) is served from disk.
      unawaited(RemoteImageDiskCache.instance.prefetch(url));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_resolved) {
      return SizedBox(width: widget.width, height: widget.height);
    }
    final cached = _cached;
    if (cached != null) {
      return Image.file(
        cached,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: widget.errorBuilder,
      );
    }
    return Image.network(
      widget.url,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      errorBuilder: widget.errorBuilder,
    );
  }
}

