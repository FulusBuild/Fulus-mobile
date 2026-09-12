import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';

/// Opt-in live contract test for the Fulus authoritative sync API.
///
/// Required environment:
///   FULUS_API_URL       Edge Function URL
///   FULUS_ACCESS_TOKEN  Supabase access token for a user with an active Fulus business membership
///   FULUS_BUSINESS_ID   Active business ID for that user
///   FULUS_DEVICE_ID     Active registered device_client_id for that business
///
/// This test creates one uniquely-named product, retries the same operation
/// (idempotency), verifies a conflicting replay is rejected, then deletes the
/// created product. It is intentionally opt-in so normal CI never mutates a
/// live database unless explicitly requested.
Future<void> main() async {
  final baseUrl = _required('FULUS_API_URL');
  final token = _required('FULUS_ACCESS_TOKEN');
  final businessId = _required('FULUS_BUSINESS_ID');
  final deviceClientId = _required('FULUS_DEVICE_ID');

  final dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    headers: {
      'content-type': 'application/json',
      'Authorization': 'Bearer $token',
      'x-fulus-device-id': deviceClientId,
    },
    validateStatus: (_) => true,
  ));

  final suffix = '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(10000)}';
  final localId = 'e2e-$suffix';
  final operationId = 'e2e-create-$suffix';
  final sku = 'E2E-$suffix';
  String? serverId;

  try {
    final createPayload = {
      'local_id': localId,
      'name': 'Fulus E2E Test Product $suffix',
      'sku': sku,
      'cost_price': 100,
      'selling_price': 150,
      'low_stock_threshold': 5,
      'is_active': true,
    };

    final first = await _submit(
      dio,
      businessId: businessId,
      operationType: 'product.create',
      operationId: operationId,
      payload: createPayload,
    );
    _expect2xx(first, 'initial product.create');

    serverId = _entityId(first);
    if (serverId == null || serverId.isEmpty) {
      throw StateError('initial product.create returned no data.entity_id');
    }

    final replay = await _submit(
      dio,
      businessId: businessId,
      operationType: 'product.create',
      operationId: operationId,
      payload: createPayload,
    );
    _expect2xx(replay, 'idempotent product.create replay');

    final replayId = _entityId(replay);
    if (replayId != serverId) {
      throw StateError(
        'idempotent replay returned entity_id=$replayId; expected $serverId',
      );
    }

    final conflictingReplay = await _submit(
      dio,
      businessId: businessId,
      operationType: 'product.create',
      operationId: operationId,
      payload: {
        ...createPayload,
        'name': 'Fulus E2E Conflicting Replay $suffix',
      },
    );

    if (conflictingReplay.statusCode == null ||
        conflictingReplay.statusCode! < 400 ||
        conflictingReplay.statusCode! >= 500) {
      throw StateError(
        'conflicting operation replay should be rejected with a 4xx; '
        'got ${conflictingReplay.statusCode}',
      );
    }

    stdout.writeln('PASS: create, idempotent replay, and conflict detection');

    final delete = await _submit(
      dio,
      businessId: businessId,
      operationType: 'product.delete',
      operationId: 'e2e-delete-$suffix',
      payload: {'server_id': serverId},
    );
    _expect2xx(delete, 'cleanup product.delete');

    stdout.writeln('PASS: cleanup');
  } finally {
    if (serverId != null) {
      try {
        final cleanup = await _submit(
          dio,
          businessId: businessId,
          operationType: 'product.delete',
          operationId: 'e2e-final-cleanup-$suffix',
          payload: {'server_id': serverId},
        );
        if (cleanup.statusCode != null &&
            cleanup.statusCode! >= 200 &&
            cleanup.statusCode! < 300) {
          stdout.writeln('Cleanup completed.');
        }
      } catch (_) {
        stderr.writeln(
          'WARNING: automatic cleanup failed for server entity $serverId.',
        );
      }
    }
  }
}

String _required(String name) {
  final value = Platform.environment[name];
  if (value == null || value.isEmpty) {
    throw StateError('$name is required for the Fulus E2E contract test.');
  }
  return value;
}

Future<Response<dynamic>> _submit(
  Dio dio, {
  required String businessId,
  required String operationType,
  required String operationId,
  required Object payload,
}) {
  return dio.post(
    '',
    data: {
      'business_id': businessId,
      'operation_type': operationType,
      'operation_id': operationId,
      'payload': payload,
    },
  );
}

void _expect2xx(Response<dynamic> response, String operation) {
  final status = response.statusCode ?? 0;
  if (status < 200 || status >= 300) {
    throw StateError(
      '$operation failed with HTTP $status: ${response.data}',
    );
  }
}

String? _entityId(Response<dynamic> response) {
  final root = response.data;
  if (root is! Map) return null;
  final data = root['data'];
  if (data is! Map) return null;
  final value = data['entity_id'];
  return value is String ? value : null;
}
