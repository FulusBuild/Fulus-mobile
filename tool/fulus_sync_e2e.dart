import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';

/// Live contract test for the Fulus authoritative sync API.
/// Catalog mutations deliberately include an operation_id so the production idempotency contract is exercised.
///
/// Required environment:
///   FULUS_API_URL       Edge Function URL
///   FULUS_BUSINESS_ID   Active business ID for the E2E user
///   FULUS_DEVICE_ID     Active registered device_client_id
///
/// Authentication requires the dedicated Supabase Auth account credentials:
///   FULUS_E2E_EMAIL     Supabase Auth email
///   FULUS_E2E_PASSWORD   Supabase Auth password
///
/// A fresh Supabase access token is minted from the email/password credentials
/// for every E2E run. Static access-token and refresh-token authentication are
/// intentionally unsupported so an expired CI token cannot become a fallback.
Future<void> main() async {
  final baseUrl = _required('FULUS_API_URL');
  final businessId = _required('FULUS_BUSINESS_ID');
  final deviceClientId = _required('FULUS_DEVICE_ID');
  final token = await _resolveAccessToken();

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

  _printIdentityFingerprint('business_id', businessId);
  _printIdentityFingerprint('device_client_id', deviceClientId);
  await _preflightDevice(dio, businessId: businessId);

  final suffix = '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(10000)}';
  final idempotencyOperationId = 'e2e-idempotency-$suffix';
  final createOperationId = 'e2e-create-$suffix';
  final deleteOperationId = 'e2e-delete-$suffix';
  final sku = 'E2E-$suffix';
  String? serverId;
  var cleanedUp = false;

  try {
    final createPayload = {
      'name': 'Fulus E2E Test Product $suffix',
      'sku': sku,
      'cost_price': 100,
      'selling_price': 150,
      'low_stock_threshold': 5,
      'is_active': true,
    };

    final create = await _submitCatalog(
      dio,
      businessId: businessId,
      action: 'catalog_upsert',
      entity: 'products',
      operationId: createOperationId,
      item: createPayload,
    );
    _expect2xx(create, 'initial product.create');

    serverId = _entityId(create);
    if (serverId == null || serverId.isEmpty) {
      throw StateError('initial product.create returned no data.item.id');
    }
    stdout.writeln('PASS: product.create');
    final productChangeSequence = await _findChangeSequence(
      dio,
      businessId: businessId,
      entityType: 'product',
      entityId: serverId,
    );
    if (productChangeSequence > 0) {
      final staleCursor = productChangeSequence - 1;
      final staleUpdate = await _submitCatalog(
        dio,
        businessId: businessId,
        action: 'catalog_upsert',
        entity: 'products',
        operationId: 'e2e-conflict-$suffix',
        baseCursor: staleCursor,
        item: {
          ...createPayload,
          'name': 'Fulus E2E stale update $suffix',
        },
        id: serverId,
      );
      final staleStatus = staleUpdate.statusCode ?? 0;
      final staleCode = staleUpdate.data is Map &&
              (staleUpdate.data as Map)['error'] is Map
          ? ((staleUpdate.data as Map)['error'] as Map)['code']
          : null;
      if (staleStatus != 409 || staleCode != 'SYNC_CONFLICT') {
        throw StateError(
          'expected optimistic concurrency conflict, got HTTP $staleStatus: ${staleUpdate.data}',
        );
      }
      stdout.writeln('PASS: stale catalog update rejected as SYNC_CONFLICT');

      final validUpdate = await _submitCatalog(
        dio,
        businessId: businessId,
        action: 'catalog_upsert',
        entity: 'products',
        operationId: 'e2e-valid-update-$suffix',
        baseCursor: productChangeSequence,
        item: {
          ...createPayload,
          'name': 'Fulus E2E valid update $suffix',
        },
        id: serverId,
      );
      _expect2xx(validUpdate, 'valid product.update after concurrency check');
      stdout.writeln('PASS: valid catalog update accepted at current cursor');
    }

    final idempotencyPayload = {
      'kind': 'e2e-idempotency-probe',
      'product_id': serverId,
      'value': sku,
    };

    final first = await _submitSyncOperation(
      dio,
      businessId: businessId,
      operationId: idempotencyOperationId,
      payload: idempotencyPayload,
    );
    _expect2xx(first, 'idempotency first submission');
    stdout.writeln('PASS: idempotency first submission');

    final replay = await _submitSyncOperation(
      dio,
      businessId: businessId,
      operationId: idempotencyOperationId,
      payload: idempotencyPayload,
    );
    _expect2xx(replay, 'idempotency same replay');
    stdout.writeln('PASS: idempotency same replay');

    final conflictingReplay = await _submitSyncOperation(
      dio,
      businessId: businessId,
      operationId: idempotencyOperationId,
      payload: {
        ...idempotencyPayload,
        'value': '$sku-conflict',
      },
    );
    final conflictHttpStatus = conflictingReplay.statusCode ?? 0;
    final conflictData = conflictingReplay.data;
    final nestedData = conflictData is Map ? conflictData['data'] : null;
    final envelopeStatus = nestedData is Map ? nestedData['status_code'] : null;
    final envelopeError = nestedData is Map ? nestedData['error'] : null;
    final envelopeErrorCode = envelopeError is Map ? envelopeError['code'] : null;
    final conflictStatus = envelopeStatus is num
        ? envelopeStatus.toInt()
        : conflictHttpStatus;

    if (conflictStatus != 409 || envelopeErrorCode != 'IDEMPOTENCY_CONFLICT') {
      throw StateError(
        'conflicting idempotency replay expected HTTP 409 or a '
        'status_code=409 IDEMPOTENCY_CONFLICT envelope, got HTTP '
        '$conflictHttpStatus: $conflictData',
      );
    }
    stdout.writeln('PASS: conflicting idempotency replay rejected');

    final delete = await _submitCatalog(
      dio,
      businessId: businessId,
      action: 'catalog_delete',
      entity: 'products',
      operationId: deleteOperationId,
      id: serverId,
    );
    _expect2xx(delete, 'cleanup product.delete');
    cleanedUp = true;
    stdout.writeln('PASS: product.delete');
  } finally {
    if (serverId != null && !cleanedUp) {
      try {
        final cleanup = await _submitCatalog(
          dio,
          businessId: businessId,
          action: 'catalog_delete',
          entity: 'products',
          operationId: '${deleteOperationId}-cleanup',
          id: serverId,
        );
        if (cleanup.statusCode != null &&
            cleanup.statusCode! >= 200 &&
            cleanup.statusCode! < 300) {
          stdout.writeln('Cleanup completed.');
        }
      } catch (_) {
        stderr.writeln(
          'WARNING: automatic cleanup failed for the test-created server entity.',
        );
      }
    }
  }

  stdout.writeln('PASS: Fulus live sync contract E2E');
}

Future<String> _resolveAccessToken() async {
  final email = _required('FULUS_E2E_EMAIL');
  final password = _required('FULUS_E2E_PASSWORD');
  final authUrl = _required('FULUS_AUTH_URL');
  final publishableKey = _required('FULUS_PUBLISHABLE_KEY');
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    headers: {
      'apikey': publishableKey,
      'content-type': 'application/json',
    },
    validateStatus: (_) => true,
  ));

  final response = await dio.post(
    '$authUrl/auth/v1/token',
    queryParameters: {'grant_type': 'password'},
    data: {
      'email': email,
      'password': password,
    },
  );
  final status = response.statusCode ?? 0;
  final data = response.data;
  final accessToken = data is Map ? data['access_token'] : null;
  if (status < 200 || status >= 300 || accessToken is! String || accessToken.isEmpty) {
    throw StateError(
      'E2E password authentication failed with HTTP $status: '
      '${_safeAuthError(data)}',
    );
  }
  stdout.writeln('PASS: fresh E2E access token minted from Supabase password authentication');
  return accessToken;
}

String _safeAuthError(dynamic data) {
  if (data is Map) {
    final error = data['error_description'] ?? data['msg'] ?? data['error'];
    if (error != null) return error.toString();
  }
  return 'authentication response did not contain an access token';
}

Future<Response<dynamic>> _submitCatalog(
  Dio dio, {
  required String businessId,
  required String action,
  required String entity,
  required String operationId,
  Map<String, dynamic>? item,
  String? id,
  int? baseCursor,
}) {
  return dio.post(
    '',
    data: {
      'business_id': businessId,
      'action': action,
      'entity': entity,
      'operation_id': operationId,
      if (baseCursor != null) 'base_cursor': baseCursor,
      if (item != null) 'item': item,
      if (id != null) 'id': id,
    },
  );
}

Future<int> _findChangeSequence(
  Dio dio, {
  required String businessId,
  required String entityType,
  required String entityId,
}) async {
  var cursor = 0;
  const limit = 500;
  for (var page = 0; page < 20; page++) {
    final response = await dio.get(
      '',
      queryParameters: {
        'business_id': businessId,
        'cursor': cursor,
        'limit': limit,
      },
    );
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw StateError(
        'E2E change-feed read failed with HTTP $status: ' + response.data.toString(),
      );
    }
    final root = response.data;
    final data = root is Map ? root['data'] : null;
    if (data is! Map) {
      throw StateError('E2E change-feed response did not contain data.');
    }
    final changes = data['changes'];
    if (changes is! List) {
      throw StateError('E2E change-feed response did not contain changes.');
    }
    for (final raw in changes) {
      if (raw is Map &&
          raw['entity_type'] == entityType &&
          raw['entity_id'] == entityId) {
        final sequence = raw['sequence'];
        if (sequence is num) return sequence.toInt();
      }
    }
    final next = data['next_cursor'];
    final hasMore = data['has_more'] == true;
    if (!hasMore || next is! num || next.toInt() <= cursor) break;
    cursor = next.toInt();
  }
  throw StateError(
    'E2E could not locate the test entity in the retained change feed.',
  );
}

Future<Response<dynamic>> _submitSyncOperation(
  Dio dio, {
  required String businessId,
  required String operationId,
  required Map<String, dynamic> payload,
}) {
  return dio.post(
    '',
    data: {
      'business_id': businessId,
      'operation_type': 'sync_operation',
      'operation_id': operationId,
      'client_reference': operationId,
      'payload': payload,
      'action': 'sync_operation',
    },
  );
}

void _printIdentityFingerprint(String label, String value) {
  final trimmed = value.trim();
  stdout.writeln(
    'E2E identity $label: length=${value.length}, '
    'trimmed_length=${trimmed.length}, fingerprint=${_fingerprint(value)}, '
    'trimmed_fingerprint=${_fingerprint(trimmed)}',
  );
}

String _fingerprint(String value) {
  // Non-secret diagnostic fingerprint. This avoids printing the actual
  // identity while making exact CI-vs-local value comparisons possible.
  var hash = 0xcbf29ce484222325;
  for (final byte in value.codeUnits) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

Future<void> _preflightDevice(
  Dio dio, {
  required String businessId,
}) async {
  final response = await dio.get(
    '',
    queryParameters: {'business_id': businessId},
  );
  final status = response.statusCode ?? 0;
  if (status < 200 || status >= 300) {
    throw StateError(
      'E2E device preflight failed with HTTP $status: ${response.data}',
    );
  }
  stdout.writeln('PASS: device authorization preflight');
}

String _required(String name) {
  final value = Platform.environment[name];
  if (value == null || value.isEmpty) {
    throw StateError('$name is required for the Fulus E2E contract test.');
  }
  return value;
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
  final item = data['item'];
  if (item is! Map) return null;
  final value = item['id'];
  return value is String ? value : null;
}
