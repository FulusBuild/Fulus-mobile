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
/// This test creates one uniquely-named product using the same catalog command
/// contract as the Flutter client, exercises the generic sync_operation
/// idempotency contract separately, then deletes the created product. It is
/// intentionally opt-in so normal CI never mutates a live database unless
/// explicitly requested.
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

  _printIdentityFingerprint('business_id', businessId);
  _printIdentityFingerprint('device_client_id', deviceClientId);
  await _preflightDevice(dio, businessId: businessId);

  final suffix =
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(10000)}';
  final idempotencyOperationId = 'e2e-idempotency-$suffix';
  final sku = 'E2E-$suffix';
  String? serverId;
  var cleanedUp = false;

  try {
    // Match the real FulusSyncApi wire contract for product.create:
    // action=catalog_upsert, entity=products, item=<product payload>.
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
      item: createPayload,
    );
    _expect2xx(create, 'initial product.create');

    serverId = _entityId(create);
    if (serverId == null || serverId.isEmpty) {
      throw StateError('initial product.create returned no data.item.id');
    }
    stdout.writeln('PASS: product.create');

    // Idempotency is a separate server contract implemented by
    // accept_sync_operation. Do not pretend catalog_upsert itself provides
    // operation-id idempotency until the backend does so explicitly.
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
    final conflictStatus = conflictingReplay.statusCode ?? 0;
    final conflictData = conflictingReplay.data;
    if (conflictStatus != 409 ||
        conflictData is! Map ||
        conflictData['error'] is! Map ||
        (conflictData['error'] as Map)['code'] != 'IDEMPOTENCY_CONFLICT') {
      throw StateError(
        'conflicting idempotency replay expected HTTP 409 '
        'IDEMPOTENCY_CONFLICT, got HTTP $conflictStatus: $conflictData',
      );
    }
    stdout.writeln('PASS: conflicting idempotency replay rejected');

    final delete = await _submitCatalog(
      dio,
      businessId: businessId,
      action: 'catalog_delete',
      entity: 'products',
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
          id: serverId,
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

  stdout.writeln('PASS: Fulus live sync contract E2E');
}

Future<Response<dynamic>> _submitCatalog(
  Dio dio, {
  required String businessId,
  required String action,
  required String entity,
  Map<String, dynamic>? item,
  String? id,
}) {
  return dio.post(
    '',
    data: {
      'business_id': businessId,
      'action': action,
      'entity': entity,
      if (item != null) 'item': item,
      if (id != null) 'id': id,
    },
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
