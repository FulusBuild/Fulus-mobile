import 'dart:io';

import 'package:dio/dio.dart';

import '../../core/config/supabase_config.dart';
import 'api_client.dart';

/// Uploads product catalog photos to Supabase Storage.
///
/// The bucket is public for reads, while writes are protected by Storage RLS
/// against the authenticated user's active business membership. The returned
/// URL is persisted on the canonical product row and therefore travels with
/// normal product sync/reconciliation.
class ProductImageApi {
  ProductImageApi(this._client);

  final ApiClient _client;

  Future<String> upload({
    required File file,
    required String businessId,
    required String productLocalId,
  }) async {
    if (!await file.exists()) {
      throw StateError('The selected product image is no longer available on this device.');
    }

    final extension = _extension(file.path);
    final contentType = switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    final objectPath = '${businessId}/${productLocalId}/${DateTime.now().microsecondsSinceEpoch}.$extension';
    final bytes = await file.readAsBytes();

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
      ),
    );

    return '${SupabaseConfig.url}/storage/v1/object/public/product-images/$objectPath';
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
