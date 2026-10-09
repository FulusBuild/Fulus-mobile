import 'dart:io';

import 'package:dio/dio.dart';

import '../../core/config/supabase_config.dart';
import '../../core/utils/image_compressor.dart';
import '../../sync/sync_error.dart';
import 'api_client.dart';

/// Uploads product catalog photos to Supabase Storage.
///
/// The bucket is public for reads, while writes are protected by Storage RLS
/// against the authenticated user's catalog permission. The returned URL is
/// persisted on the canonical product row and therefore travels with normal
/// product sync/reconciliation.
///
/// Every failure leaves this class as a [SyncFailure] with a stable kind, so
/// the sync engine can tell a flaky network (retry) from a rejected file
/// (park for attention) without guessing from exception text.
class ProductImageApi {
  ProductImageApi(this._client);

  final ApiClient _client;

  /// Photos larger than this are re-compressed before upload. Photos stored by
  /// older app versions were never compressed.
  static const int _recompressAboveBytes = 1500 * 1024;

  Future<String> upload({
    required File file,
    required String businessId,
    required String productLocalId,
  }) async {
    if (!await file.exists()) {
      throw const SyncFailure(
        kind: SyncErrorKind.permanentNotFound,
        message: 'The selected product image is no longer available on this device.',
      );
    }

    var source = file;
    if (await source.length() > _recompressAboveBytes) {
      source = await compressImageFile(source);
    }
    final bytes = await source.readAsBytes();
    if (bytes.length > kMaxProductImageBytes) {
      throw const SyncFailure(
        kind: SyncErrorKind.validation,
        message: 'The product image is too large to upload (5 MB maximum).',
      );
    }

    final extension = _extension(source.path);
    final contentType = switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    final objectPath = '$businessId/$productLocalId/${DateTime.now().microsecondsSinceEpoch}.$extension';

    try {
      await _client.dio.post(
        '${SupabaseConfig.url}/storage/v1/object/product-images/$objectPath',
        data: bytes,
        options: Options(
          headers: {
            'apikey': SupabaseConfig.publishableKey,
            'content-type': contentType,
            'cache-control': '31536000',
            'x-upsert': 'false',
          },
          // The shared client's generic retry layer waits up to ~12 minutes
          // per request on connection errors. This call runs inside the
          // single-file outbox drain, so that wait would stall every other
          // queued item. Fail fast; the queue's own backoff handles retries.
          extra: {'skip_generic_retry': true},
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
    } on DioException catch (error) {
      throw _classify(error);
    }

    return '${SupabaseConfig.url}/storage/v1/object/public/product-images/$objectPath';
  }

  static SyncFailure _classify(DioException error) {
    final status = error.response?.statusCode;
    if (status == null) {
      return SyncFailure(
        kind: SyncErrorKind.network,
        message: 'Could not reach Fulus Cloud to upload the product image.',
        cause: error,
      );
    }
    // Transient: server trouble, throttling, a token the auth layer could not
    // refresh yet, or an object-name collision (the next attempt uses a new name).
    if (status >= 500 || status == 401 || status == 408 || status == 409 || status == 429) {
      return SyncFailure(
        kind: SyncErrorKind.temporaryServer,
        message: 'Fulus Cloud could not accept the product image yet (HTTP $status).',
        cause: error,
      );
    }
    if (status == 403) {
      return SyncFailure(
        kind: SyncErrorKind.permission,
        message: 'This account is not allowed to upload product images.',
        cause: error,
      );
    }
    // 400/404/413/415/422...: the request itself is wrong; retrying cannot help.
    return SyncFailure(
      kind: SyncErrorKind.validation,
      message: 'Fulus Cloud rejected the product image (HTTP $status).',
      cause: error,
    );
  }

  String _extension(String path) {
    final dot = path.lastIndexOf('.');
    final extension = dot >= 0 ? path.substring(dot + 1).toLowerCase() : 'jpg';
    return switch (extension) {
      'png' => 'png',
      'webp' => 'webp',
      _ => 'jpg',
    };
  }
}
