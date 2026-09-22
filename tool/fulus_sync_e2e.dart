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
  await _verifyBusinessProvisioningIdempotency(
    authUrl: _required('FULUS_AUTH_URL'),
    publishableKey: _required('FULUS_PUBLISHABLE_KEY'),
    token: token,
    businessId: businessId,
  );

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
  final suffix = '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(10000)}';
  final idempotencyOperationId = 'e2e-idempotency-$suffix';
  final createOperationId = 'e2e-create-$suffix';
  final deleteOperationId = 'e2e-delete-$suffix';
  final sku = 'E2E-$suffix';
  String? serverId;
  var cleanedUp = false;
  String? e2eLocationId;

  try {
    final preflight = await _preflightDevice(dio, businessId: businessId);
    if (preflight == _PreflightResult.cursorTooOld) {
      await _verifyAuthoritativeRecoverySnapshot(
        dio,
        businessId: businessId,
      );
      stdout.writeln('PASS: authoritative restore snapshot exposes a valid recovery boundary');
      final freshDeviceId = 'e2e-${suffix.replaceAll(RegExp(r'[^a-zA-Z0-9-]'), '')}';
      await _registerEphemeralDevice(dio, businessId: businessId, deviceClientId: freshDeviceId);
      dio.options.headers['x-fulus-device-id'] = freshDeviceId;
      // A newly registered device also starts at cursor 0. Because the
      // retained feed is already compacted, it must enter bootstrap/restore
      // rather than pretending incremental sync is sufficient. The contract
      // E2E therefore stops using the sync feed for preflight after verifying
      // the guard and exercises authenticated command/idempotency paths with
      // the fresh device.
      stdout.writeln('PASS: fresh device registered after stale-cursor guard');
    }

    e2eLocationId = await _findFirstLocationId(dio, businessId: businessId);
    if (e2eLocationId == null) {
      throw StateError('Live sync E2E business has no location for stock-adjustment verification.');
    }

    // Exercise the two finance/sales paths that are easy to miss in catalog-only E2E:
    // miscellaneous income and a Quick Sale line with no catalog product.
    final incomeOperationId = 'e2e-income-$suffix';
    final incomeResponse = await dio.post('', data: {
      'action': 'income_create',
      'business_id': businessId,
      'operation_id': incomeOperationId,
      'client_reference': incomeOperationId,
      'location_id': e2eLocationId,
      'source': 'E2E miscellaneous income $suffix',
      'amount': 12345,
      'income_date': DateTime.now().toUtc().toIso8601String(),
      'notes': 'Cloud Sync V1 income contract',
    });
    _expect2xx(incomeResponse, 'income.create');
    final incomeData = incomeResponse.data is Map ? incomeResponse.data['data'] : null;
    if (incomeData is! Map || incomeData['income_id'] is! String) {
      throw StateError('income.create returned no income_id: ${incomeResponse.data}');
    }
    stdout.writeln('PASS: income.create');

    final quickSaleOperationId = 'e2e-quick-sale-$suffix';
    final quickSaleResponse = await dio.post('', data: {
      'action': 'sale_create',
      'business_id': businessId,
      'operation_id': quickSaleOperationId,
      'client_reference': quickSaleOperationId,
      'location_id': e2eLocationId,
      'sale_date': DateTime.now().toUtc().toIso8601String(),
      'discount': 0,
      'tax': 0,
      'amount_paid': 321,
      'payment_method': 'cash',
      'notes': 'Cloud Sync V1 Quick Sale contract',
      'items': [
        {
          'product_id': null,
          'description': 'E2E Quick Sale $suffix',
          'quantity': 1,
          'unit_price': 321,
          'cost_price_at_sale': 0,
        },
      ],
    });
    _expect2xx(quickSaleResponse, 'sale.create Quick Sale');
    final quickSaleData = quickSaleResponse.data is Map ? quickSaleResponse.data['data'] : null;
    if (quickSaleData is! Map || quickSaleData['sale_id'] is! String) {
      throw StateError('Quick Sale returned no sale_id: ${quickSaleResponse.data}');
    }
    stdout.writeln('PASS: sale.create Quick Sale');

    final createPayload = {
      'name': 'Fulus E2E Test Product $suffix',
      'sku': sku,
      'cost_price': 100,
      'selling_price': 150,
      'low_stock_threshold': 5,
      'is_active': true,
      'tracks_stock': true,
      // Product creation now requires the authoritative stock location.
      // Seed a non-zero quantity so this E2E proves initial local stock
      // survives the first cloud reconciliation instead of being reset to 0.
      'initial_stock': 17,
      'location_id': e2eLocationId,
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

    final initialSnapshot = await dio.post(
      '',
      data: {'action': 'restore_snapshot', 'business_id': businessId},
    );
    _expect2xx(initialSnapshot, 'restore snapshot after product.create');
    final initialSnapshotData = initialSnapshot.data is Map
        ? (initialSnapshot.data as Map)['data']
        : null;
    final initialStockLevels = initialSnapshotData is Map
        ? initialSnapshotData['product_stock_levels']
        : null;
    if (initialStockLevels is! List) {
      throw StateError('Initial product snapshot did not contain product_stock_levels.');
    }
    final initialMatches = initialStockLevels.where((raw) {
      if (raw is! Map) return false;
      return raw['product_id'] == serverId &&
          raw['location_id'] == e2eLocationId;
    }).toList();
    if (initialMatches.length != 1) {
      throw StateError(
        'Expected exactly one initial stock level for the E2E product/location, '
        'got ${initialMatches.length}.',
      );
    }
    final initialCommittedStock = (initialMatches.single as Map)['current_stock'];
    if (initialCommittedStock is! num || initialCommittedStock.toInt() != 17) {
      throw StateError(
        'Initial product stock was not preserved authoritatively: '
        '$initialCommittedStock',
      );
    }
    stdout.writeln('PASS: product.create preserves initial stock at its location');

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

    final stockProductId = serverId;
    final stockLocationId = e2eLocationId;
    final stockResults = await Future.wait([
      _submitInventorySet(dio, businessId: businessId, operationId: 'e2e-stock-a-$suffix', productId: stockProductId, locationId: stockLocationId, newQuantity: 101),
      _submitInventorySet(dio, businessId: businessId, operationId: 'e2e-stock-b-$suffix', productId: stockProductId, locationId: stockLocationId, newQuantity: 202),
    ]);
    const requestedTargets = [101, 202];
    for (var i = 0; i < stockResults.length; i++) {
      final response = stockResults[i];
      _expect2xx(response, 'concurrent absolute stock adjustment');
      final data = response.data is Map ? (response.data as Map)['data'] : null;
      final current = data is Map ? data['current_stock'] : null;
      if (current is! num || current.toInt() != requestedTargets[i]) {
        throw StateError(
          'Concurrent absolute stock adjustment did not return its requested '
          'authoritative target ${requestedTargets[i]}: ${response.data}',
        );
      }
    }

    final snapshot = await dio.post(
      '',
      data: {'action': 'restore_snapshot', 'business_id': businessId},
    );
    _expect2xx(snapshot, 'restore snapshot after concurrent stock adjustment');
    final snapshotData = snapshot.data is Map ? (snapshot.data as Map)['data'] : null;
    final stockLevels = snapshotData is Map ? snapshotData['product_stock_levels'] : null;
    if (stockLevels is! List) {
      throw StateError('Recovery snapshot did not contain product_stock_levels.');
    }
    final matchingStock = stockLevels.where((raw) {
      if (raw is! Map) return false;
      return raw['product_id'] == stockProductId && raw['location_id'] == stockLocationId;
    }).toList();
    if (matchingStock.length != 1) {
      throw StateError(
        'Expected exactly one stock level for the E2E product/location, got ${matchingStock.length}.',
      );
    }
    final committedStock = (matchingStock.single as Map)['current_stock'];
    if (committedStock is! num ||
        (committedStock.toInt() != 101 && committedStock.toInt() != 202)) {
      throw StateError(
        'Concurrent absolute stock adjustment committed invalid stock: ${committedStock}',
      );
    }
    stdout.writeln('PASS: concurrent absolute stock adjustments serialize to requested targets');

    final inventoryReplay = await _submitInventorySet(
      dio,
      businessId: businessId,
      operationId: 'e2e-inventory-replay-$suffix',
      productId: stockProductId,
      locationId: stockLocationId,
      newQuantity: 303,
    );
    _expect2xx(inventoryReplay, 'inventory idempotency first submission');

    final inventorySameReplay = await _submitInventorySet(
      dio,
      businessId: businessId,
      operationId: 'e2e-inventory-replay-$suffix',
      productId: stockProductId,
      locationId: stockLocationId,
      newQuantity: 303,
    );
    _expect2xx(inventorySameReplay, 'inventory idempotency same replay');

    final inventoryConflictingReplay = await _submitInventorySet(
      dio,
      businessId: businessId,
      operationId: 'e2e-inventory-replay-$suffix',
      productId: stockProductId,
      locationId: stockLocationId,
      newQuantity: 404,
    );
    final inventoryConflictStatus = inventoryConflictingReplay.statusCode ?? 0;
    final inventoryConflictData = inventoryConflictingReplay.data;
    final inventoryConflictError = inventoryConflictData is Map
        ? inventoryConflictData['error']
        : null;
    final inventoryConflictCode = inventoryConflictError is Map
        ? inventoryConflictError['code']
        : null;
    if (inventoryConflictStatus != 409 ||
        inventoryConflictCode != 'IDEMPOTENCY_CONFLICT') {
      throw StateError(
        'conflicting inventory idempotency replay expected HTTP 409 IDEMPOTENCY_CONFLICT, '
        'got HTTP $inventoryConflictStatus: $inventoryConflictData',
      );
    }
    stdout.writeln('PASS: conflicting inventory replay rejected');

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

Future<String?> _findFirstLocationId(Dio dio, {required String businessId}) async {
  final response = await dio.post('', data: {'action': 'restore_snapshot', 'business_id': businessId});
  _expect2xx(response, 'restore snapshot for stock-adjustment E2E');
  final root = response.data;
  final data = root is Map ? root['data'] : null;
  final locations = data is Map ? data['locations'] : null;
  if (locations is! List || locations.isEmpty) return null;
  final first = locations.first;
  if (first is! Map) return null;
  final id = first['id'];
  return id is String && id.isNotEmpty ? id : null;
}

Future<Response<dynamic>> _submitInventorySet(Dio dio, {required String businessId, required String operationId, required String productId, required String locationId, required int newQuantity}) {
  return dio.post('', data: {
    'action': 'inventory_set', 'business_id': businessId, 'operation_id': operationId,
    'client_reference': operationId, 'product_id': productId, 'location_id': locationId,
    'new_quantity': newQuantity, 'reason': 'Fulus concurrent stock-adjustment E2E',
  });
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
  var recoveredFromRetention = false;
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
    if (status == 410 && !recoveredFromRetention) {
      final root = response.data;
      final error = root is Map ? root['error'] : null;
      final oldest = error is Map ? error['oldest_sequence'] : null;
      final bootstrapRequired = error is Map && error['bootstrap_required'] == true;
      if (bootstrapRequired && oldest is num) {
        // The E2E has already exercised the 410 guard in preflight. For this
        // assertion we need to inspect the retained feed after a successful
        // mutation, so resume from the first retained sequence rather than
        // treating an intentionally compacted history as a test failure.
        cursor = max(0, oldest.toInt() - 1);
        recoveredFromRetention = true;
        continue;
      }
    }
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

enum _PreflightResult { ok, cursorTooOld }

Future<_PreflightResult> _preflightDevice(
  Dio dio, {
  required String businessId,
}) async {
  final response = await dio.get(
    '',
    queryParameters: {'business_id': businessId},
  );
  final status = response.statusCode ?? 0;
  if (status == 410 && response.data is Map && (response.data as Map)['error'] is Map && ((response.data as Map)['error'] as Map)['code'] == 'SYNC_CURSOR_TOO_OLD') {
    stdout.writeln('PASS: stale sync cursor correctly rejected with SYNC_CURSOR_TOO_OLD');
    return _PreflightResult.cursorTooOld;
  }
  if (status < 200 || status >= 300) {
    throw StateError(
      'E2E device preflight failed with HTTP $status: ${response.data}',
    );
  }
  stdout.writeln('PASS: device authorization preflight');
  return _PreflightResult.ok;
}

Future<void> _verifyAuthoritativeRecoverySnapshot(
  Dio dio, {
  required String businessId,
}) async {
  final response = await dio.post(
    '',
    data: {
      'action': 'restore_snapshot',
      'business_id': businessId,
    },
  );
  _expect2xx(response, 'authoritative restore snapshot');
  final root = response.data;
  final data = root is Map ? root['data'] : null;
  if (data is! Map) {
    throw StateError('restore_snapshot response did not contain data.');
  }
  final boundary = data['sync_boundary'];
  if (boundary is! num || boundary.toInt() < 0) {
    throw StateError('restore_snapshot returned an invalid sync_boundary.');
  }
  if (data['business'] is! Map) {
    throw StateError('restore_snapshot response did not contain business state.');
  }
}

Future<void> _registerEphemeralDevice(
  Dio dio, {
  required String businessId,
  required String deviceClientId,
}) async {
  final response = await dio.post(
    '',
    data: {
      'business_id': businessId,
      'action': 'register_device',
      'device_client_id': deviceClientId,
      'device_name': 'Fulus CI E2E ephemeral device',
      'platform': 'ci',
      'app_version': 'e2e',
    },
  );
  _expect2xx(response, 'register ephemeral E2E device');
  stdout.writeln('PASS: ephemeral E2E device registered');
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


Future<void> _verifyBusinessProvisioningIdempotency({
  required String authUrl,
  required String publishableKey,
  required String token,
  required String businessId,
}) async {
  final dio = Dio(BaseOptions(
    baseUrl: '$authUrl/functions/v1/fulus-provision-business',
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    headers: {
      'apikey': publishableKey,
      'Authorization': 'Bearer $token',
      'content-type': 'application/json',
    },
    validateStatus: (_) => true,
  ));

  Future<Response<dynamic>> provision() {
    return dio.post(
      '',
      data: {
        'name': 'Fulus E2E Test Business',
        'currency_code': 'NGN',
        'timezone': 'Africa/Lagos',
        'location_name': 'Main',
      },
    );
  }

  final first = await provision();
  _expect2xx(first, 'business provisioning idempotency first call');
  final firstRoot = first.data;
  final firstData = firstRoot is Map ? firstRoot['data'] : null;
  final firstBusinessId = firstData is Map ? firstData['business_id'] : null;
  final firstCreated = firstData is Map ? firstData['created'] : null;
  if (firstBusinessId != businessId || firstCreated != false) {
    throw StateError(
      'business provisioning ensure returned unexpected first result: ' + first.data.toString(),
    );
  }

  final replay = await provision();
  _expect2xx(replay, 'business provisioning idempotency replay');
  final replayRoot = replay.data;
  final replayData = replayRoot is Map ? replayRoot['data'] : null;
  final replayBusinessId = replayData is Map ? replayData['business_id'] : null;
  final replayCreated = replayData is Map ? replayData['created'] : null;
  if (replayBusinessId != businessId || replayCreated != false) {
    throw StateError(
      'business provisioning replay was not idempotent: ' + replay.data.toString(),
    );
  }

  stdout.writeln('PASS: account business provisioning is idempotent for an existing cloud account');
}
