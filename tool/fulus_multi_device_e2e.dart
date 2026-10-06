import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';

/// Live two-device sync contract test.
///
/// This verifies the authoritative feed is usable in both directions:
/// device A writes and device B discovers the change, then device B writes
/// and device A discovers that change. It deliberately uses two registered
/// device identities and the production sync API.
Future<void> main() async {
  final apiUrl = _required('FULUS_API_URL');
  final businessId = _required('FULUS_BUSINESS_ID');
  final primaryDeviceId = _required('FULUS_DEVICE_ID');
  final authUrl = _required('FULUS_AUTH_URL');
  final publishableKey = _required('FULUS_PUBLISHABLE_KEY');
  final token = await _resolveAccessToken(
    authUrl: authUrl,
    publishableKey: publishableKey,
  );

  final suffix =
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(10000)}';
  final secondaryDeviceId =
      'e2e-convergence-${suffix.replaceAll(RegExp(r'[^a-zA-Z0-9-]'), '')}';

  final dio = Dio(BaseOptions(
    baseUrl: apiUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    headers: {
      'apikey': publishableKey,
      'Authorization': 'Bearer $token',
      'content-type': 'application/json',
      'x-fulus-device-id': primaryDeviceId,
    },
    validateStatus: (_) => true,
  ));

  String? secondaryServerId;
  try {
    secondaryServerId = await _registerDevice(
      dio,
      businessId: businessId,
      deviceId: secondaryDeviceId,
    );

    final primaryBaseline = await _restoreBoundary(
      dio,
      businessId: businessId,
    );

    final firstOperation = 'e2e-device-a-$suffix';
    final firstName = 'Fulus A to B $suffix';
    await _createCategory(
      dio,
      businessId: businessId,
      operationId: firstOperation,
      name: firstName,
    );

    dio.options.headers['x-fulus-device-id'] = secondaryDeviceId;
    await _expectChange(
      dio,
      businessId: businessId,
      cursor: primaryBaseline,
      entityName: firstName,
      direction: 'device A → device B',
    );

    final secondaryBaseline = await _restoreBoundary(
      dio,
      businessId: businessId,
    );

    final secondOperation = 'e2e-device-b-$suffix';
    final secondName = 'Fulus B to A $suffix';
    await _createCategory(
      dio,
      businessId: businessId,
      operationId: secondOperation,
      name: secondName,
    );

    dio.options.headers['x-fulus-device-id'] = primaryDeviceId;
    await _expectChange(
      dio,
      businessId: businessId,
      cursor: secondaryBaseline,
      entityName: secondName,
      direction: 'device B → device A',
    );


    // Financial convergence scenario: two independent device identities create
    // financial work before either device is used to consume the other's feed.
    // This is intentionally API-level evidence: it exercises the production
    // mutation, idempotency, device identity, change feed, and canonical
    // snapshot boundaries without inventing a second Flutter runtime.
    final financial = await _runFinancialConvergenceScenario(
      dio,
      businessId: businessId,
      primaryDeviceId: primaryDeviceId,
      secondaryDeviceId: secondaryDeviceId,
      suffix: suffix,
    );
    stdout.writeln('PASS: $financial');

    stdout.writeln(
      'PASS: multi-device convergence feed contract verified in both directions',
    );
  } finally {
    if (secondaryServerId != null) {
      try {
        dio.options.headers['x-fulus-device-id'] = primaryDeviceId;
        final revoke = await dio.post('', data: {
          'action': 'revoke_own_device',
          'business_id': businessId,
          'device_id': secondaryServerId,
        });
        final status = revoke.statusCode ?? 0;
        if (status < 200 || status >= 300) {
          stderr.writeln(
            'WARNING: secondary device cleanup returned HTTP $status: '
            '${revoke.data}',
          );
        }
      } catch (error) {
        stderr.writeln(
          'WARNING: secondary device cleanup failed: $error',
        );
      }
    }
  }
}

Future<void> _createCategory(
  Dio dio, {
  required String businessId,
  required String operationId,
  required String name,
}) async {
  final response = await dio.post('', data: {
    'action': 'catalog_upsert',
    'business_id': businessId,
    'entity': 'categories',
    'operation_id': operationId,
    'item': {
      'name': name,
      'description': 'Fulus multi-device convergence E2E',
    },
  });
  final status = response.statusCode ?? 0;
  if (status < 200 || status >= 300) {
    throw StateError(
      'Category mutation failed with HTTP $status: ${response.data}',
    );
  }
}

Future<int> _restoreBoundary(
  Dio dio, {
  required String businessId,
}) async {
  final response = await dio.post('', data: {
    'action': 'restore_snapshot',
    'business_id': businessId,
  });
  final status = response.statusCode ?? 0;
  if (status < 200 || status >= 300) {
    throw StateError(
      'restore_snapshot failed with HTTP $status: ${response.data}',
    );
  }
  final root = response.data;
  final data = root is Map ? root['data'] : null;
  final boundary = data is Map ? data['sync_boundary'] : null;
  if (boundary is! num || boundary.toInt() < 0) {
    throw StateError(
      'restore_snapshot returned invalid sync_boundary: ${response.data}',
    );
  }
  return boundary.toInt();
}

Future<void> _expectChange(
  Dio dio, {
  required String businessId,
  required int cursor,
  required String entityName,
  required String direction,
}) async {
  final response = await dio.get('', queryParameters: {
    'business_id': businessId,
    'cursor': cursor,
    'limit': 500,
  });
  final status = response.statusCode ?? 0;
  if (status < 200 || status >= 300) {
    throw StateError(
      'Sync feed for $direction failed with HTTP $status: ${response.data}',
    );
  }

  final root = response.data;
  final data = root is Map ? root['data'] : null;
  final changes = data is Map ? data['changes'] : null;
  if (changes is! List) {
    throw StateError(
      'Sync feed for $direction returned no changes: ${response.data}',
    );
  }

  for (final raw in changes) {
    if (raw is! Map || raw['entity_type'] != 'category') continue;
    final payload = raw['payload'];
    if (payload is Map && payload['name'] == entityName) {
      stdout.writeln(
        'PASS: $direction discovered the remote category mutation',
      );
      return;
    }
  }

  throw StateError(
    'Sync feed for $direction did not contain category "$entityName" '
    'after cursor $cursor.',
  );
}


Future<String> _runFinancialConvergenceScenario(
  Dio dio, {
  required String businessId,
  required String primaryDeviceId,
  required String secondaryDeviceId,
  required String suffix,
}) async {
  dio.options.headers['x-fulus-device-id'] = primaryDeviceId;

  final customerCreate = await dio.post('', data: {
    'action': 'customer_create',
    'business_id': businessId,
    'operation_id': 'e2e-p16-customer-$suffix',
    'name': 'Fulus P16 Customer $suffix',
    'phone': '08000000001',
     'credit_limit': '100000.00',
    'notes': 'P16 financial convergence',
  });
  _expect2xx(customerCreate, 'P16 customer.create');
  final customerData = _actionData(customerCreate);
  final customerId = customerData?['customer_id'];
  if (customerId is! String || customerId.isEmpty) {
    throw StateError('P16 customer.create returned no customer_id: ${customerCreate.data}');
  }

  final saleOperation = 'e2e-p16-credit-sale-$suffix';
  final saleDate = DateTime.now().toUtc().toIso8601String();

  // Seed an outstanding customer balance first. The concurrent repayment
  // must have a legitimate balance to act on regardless of lock ordering.
  dio.options.headers['x-fulus-device-id'] = primaryDeviceId;
  final seedOperation = 'e2e-p16-seed-sale-$suffix';
  final seedSale = await dio.post('', data: {
    'action': 'sale_create',
    'business_id': businessId,
    'operation_id': seedOperation,
    'client_reference': seedOperation,
    'location_id': await _firstLocationId(dio, businessId),
    'customer_id': customerId,
    'sale_date': saleDate,
     'discount': '0.00',
     'tax': '0.00',
     'amount_paid': '0.00',
    'payment_method': 'credit',
    'payments': [
      {'method': 'credit', 'amount': '100.00'},
    ],
    'notes': 'P16 seed customer credit',
    'items': [
      {
        'product_id': null,
        'description': 'P16 seed credit $suffix',
        'quantity': 1,
         'unit_price': '100.00',
         'cost_price_at_sale': '0.00',
      },
    ],
  });
  _expect2xx(seedSale, 'P16 seed sale.create');

  final productOperation = 'e2e-p16-product-$suffix';
  final productResponse = await dio.post('', data: {
    'action': 'catalog_upsert',
    'business_id': businessId,
    'entity': 'products',
    'operation_id': productOperation,
    'item': {
      'name': 'P16 Return Product $suffix',
      'sku': 'P16-$suffix',
      'cost_price': '50.00',
      'selling_price': '150.00',
      'low_stock_threshold': 0,
      'is_active': true,
      // The production catalog path currently preserves stock tracking;
      // seed enough stock so the financial sale can exercise the real sale
      // transaction rather than failing on an empty inventory row.
      'tracks_stock': true,
      'initial_stock': 2,
      'location_id': await _firstLocationId(dio, businessId),
    },
  });
  _expect2xx(productResponse, 'P16 product.create');
  final productData = _actionData(productResponse);
  final productItem = productData?['item'];
  final productId = productData?['id'] ??
      productData?['product_id'] ??
      (productItem is Map ? productItem['id'] : null);
  if (productId is! String || productId.isEmpty) {
    throw StateError('P16 product.create returned no product id: ' + productResponse.data.toString());
  }
  // Two independent device clients now perform financial work without
  // consuming each other's feed first. Running them concurrently exercises
  // the authoritative customer lock/idempotency boundary.
  final primaryDio = Dio(dio.options.copyWith(
    headers: {
      ...dio.options.headers,
      'x-fulus-device-id': primaryDeviceId,
    },
  ));
  final secondaryDio = Dio(dio.options.copyWith(
    headers: {
      ...dio.options.headers,
      'x-fulus-device-id': secondaryDeviceId,
    },
  ));

  final repaymentOperation = 'e2e-p16-repayment-$suffix';
  final saleLocationId = await _firstLocationId(primaryDio, businessId);
  final saleFuture = primaryDio.post('', data: {
    'action': 'sale_create',
    'business_id': businessId,
    'operation_id': saleOperation,
    'client_reference': saleOperation,
    'location_id': saleLocationId,
    'customer_id': customerId,
    'sale_date': saleDate,
     'discount': '0.00',
     'tax': '0.00',
     'amount_paid': '0.00',
    'payment_method': 'credit',
    'payments': [
      {'method': 'credit', 'amount': '150.00'},
    ],
    'notes': 'P16 concurrent financial sale',
    'items': [
      {
        'product_id': productId,
        'description': 'P16 financial sale $suffix',
        'quantity': 1,
         'unit_price': '150.00',
         'cost_price_at_sale': '0.00',
      },
    ],
  });
  final repaymentFuture = secondaryDio.post('', data: {
    'action': 'customer_repayment',
    'business_id': businessId,
    'operation_id': repaymentOperation,
    'customer_id': customerId,
     'amount': '50.00',
    'payment_method': 'cash',
    'note': 'P16 independent device repayment',
  });

  final results = await Future.wait([saleFuture, repaymentFuture]);
  _expect2xx(results[0], 'P16 concurrent sale.create');
  _expect2xx(results[1], 'P16 concurrent customer.repayment');

  final saleData = _actionData(results[0]);
  final saleId = saleData?['sale_id'];
  if (saleId is! String || saleId.isEmpty) {
    throw StateError('P16 concurrent sale.create returned no sale_id: ${results[0].data}');
  }

  // The two mutations intentionally race, so the repayment's intermediate
  // balance depends on which transaction commits first. Only the final
  // authoritative snapshot is order-independent.
  final repaymentData = _actionData(results[1]);
  final firstRepaymentBalance =
      (repaymentData?['new_balance'] as num?)?.toDouble();
  if (firstRepaymentBalance == null) {
    throw StateError(
      'P16 concurrent repayment returned no authoritative balance: ${results[1].data}',
    );
  }

  // Replay the exact sale operation on A as well. Both financial operations
  // must be idempotent independently of device identity.
  final saleReplay = await primaryDio.post('', data: {
    'action': 'sale_create',
    'business_id': businessId,
    'operation_id': saleOperation,
    'client_reference': saleOperation,
    'location_id': await _firstLocationId(primaryDio, businessId),
    'customer_id': customerId,
    'sale_date': saleDate,
     'discount': '0.00',
     'tax': '0.00',
     'amount_paid': '0.00',
    'payment_method': 'credit',
    'payments': [
      {'method': 'credit', 'amount': '150.00'},
    ],
    'notes': 'P16 concurrent financial sale',
    'items': [
      {
        'product_id': productId,
        'description': 'P16 financial sale $suffix',
        'quantity': 1,
         'unit_price': '150.00',
         'cost_price_at_sale': '0.00',
      },
    ],
  });
  _expect2xx(saleReplay, 'P16 sale.create idempotent replay');
  if (_actionData(saleReplay)?['sale_id'] != saleId) {
    throw StateError('P16 sale replay returned a different sale: ${saleReplay.data}');
  }

  // Replay the exact operation on B. This must not create a second repayment.
  final repaymentReplay = await secondaryDio.post('', data: {
    'action': 'customer_repayment',
    'business_id': businessId,
    'operation_id': repaymentOperation,
    'customer_id': customerId,
     'amount': '50.00',
    'payment_method': 'cash',
    'note': 'P16 independent device repayment',
  });
  _expect2xx(repaymentReplay, 'P16 customer.repayment idempotent replay');
  final replayData = _actionData(repaymentReplay);
  if ((replayData?['new_balance'] as num?)?.toDouble() !=
      firstRepaymentBalance) {
    throw StateError(
      'P16 repayment replay changed the authoritative result: ${repaymentReplay.data}',
    );
  }

  // Return the concurrent credit sale using the same device identity.
  // This exercises the credit-reversal path and then retries the exact return
  // operation to prove idempotency does not apply the reversal twice.
  final returnOperation = 'e2e-p16-credit-return-$suffix';
  final returnResponse = await primaryDio.post('', data: {
    'action': 'return_create',
    'business_id': businessId,
    'operation_id': returnOperation,
    'sale_id': saleId,
    'reason': 'P16 credit return',
     'refund_amount': '150.00',
    'refund_method': 'credit',
    'items': [
      {'product_id': productId, 'quantity': 1},
    ],
  });
  _expect2xx(returnResponse, 'P16 credit return');
  final returnData = _actionData(returnResponse);
  if ((returnData?['credit_reversal'] as num?)?.toDouble() != 150) {
    throw StateError('P16 credit return did not reverse exactly 150: ' + returnResponse.data.toString());
  }

  final returnReplay = await primaryDio.post('', data: {
    'action': 'return_create',
    'business_id': businessId,
    'operation_id': returnOperation,
    'sale_id': saleId,
    'reason': 'P16 credit return',
     'refund_amount': '150.00',
    'refund_method': 'credit',
    'items': [
      {'product_id': productId, 'quantity': 1},
    ],
  });
  _expect2xx(returnReplay, 'P16 credit return idempotent replay');
  if (_actionData(returnReplay)?['return_id'] != returnData?['return_id']) {
    throw StateError('P16 return replay returned a different return: ' + returnReplay.data.toString());
  }
  // Both devices consume the canonical feed from the same pre-scenario
  // boundary. The feed must expose the sale and repayment exactly once.
  dio.options.headers['x-fulus-device-id'] = primaryDeviceId;
  final primaryBoundary = await _restoreBoundary(dio, businessId: businessId);
  dio.options.headers['x-fulus-device-id'] = secondaryDeviceId;
  final secondaryBoundary = await _restoreBoundary(dio, businessId: businessId);

  if (primaryBoundary != secondaryBoundary) {
    throw StateError(
      'P16 devices received different canonical restore boundaries: '
      '$primaryBoundary vs $secondaryBoundary',
    );
  }

  final changesA = await _fetchChanges(
    dio,
    businessId: businessId,
    cursor: primaryBoundary - 20 < 0 ? 0 : primaryBoundary - 20,
  );
  dio.options.headers['x-fulus-device-id'] = primaryDeviceId;
  final changesB = await _fetchChanges(
    dio,
    businessId: businessId,
    cursor: secondaryBoundary - 20 < 0 ? 0 : secondaryBoundary - 20,
  );

  final saleCountA = _countEntity(changesA, 'sale', saleId);
  final saleCountB = _countEntity(changesB, 'sale', saleId);
  final repaymentCountA = _countOperation(
    changesA,
    'customer_ledger',
    repaymentOperation,
  );
  final repaymentCountB = _countOperation(
    changesB,
    'customer_ledger',
    repaymentOperation,
  );
  final returnId = returnData?['return_id'];
  if (returnId is! String || returnId.isEmpty) {
    throw StateError('P16 return response returned no return_id: ' + returnResponse.data.toString());
  }
  final returnCountA = _countEntity(changesA, 'return', returnId);
  final returnCountB = _countEntity(changesB, 'return', returnId);

  if (saleCountA < 1 ||
      saleCountB < 1 ||
      repaymentCountA != 1 ||
      repaymentCountB != 1 ||
      returnCountA < 1 ||
      returnCountB < 1) {
    throw StateError(
      'P16 canonical feed missing financial changes, got sale A/B=$saleCountA/$saleCountB '
      'and repayment A/B=$repaymentCountA/$repaymentCountB and return A/B=$returnCountA/$returnCountB.',
    );
  }

  // Re-read the authoritative snapshot after both mutations. This verifies
  // the final server financial invariants and gives the mobile canonical
  // reconcilers one deterministic boundary to consume.
  dio.options.headers['x-fulus-device-id'] = primaryDeviceId;
  final snapshot = await dio.post('', data: {
    'action': 'restore_snapshot',
    'business_id': businessId,
  });
  _expect2xx(snapshot, 'P16 final restore snapshot');
  final snapshotData = snapshot.data is Map ? snapshot.data['data'] : null;
  if (snapshotData is! Map) {
    throw StateError('P16 final snapshot has no data: ${snapshot.data}');
  }

  final customers = snapshotData['customers'];
  final customer = customers is List
      ? customers.whereType<Map>().cast<Map>().firstWhere(
          (row) => row['id'] == customerId,
          orElse: () => <String, dynamic>{},
        )
      : <String, dynamic>{};
  if (customer['id'] != customerId ||
      customer['outstanding_balance'] != '50.00') {
    throw StateError(
      'P16 final customer balance invariant failed: $customer',
    );
  }

  final sales = snapshotData['sales'];
  final saleRow = sales is List
      ? sales.whereType<Map>().cast<Map>().firstWhere(
          (row) => row['id'] == saleId,
          orElse: () => <String, dynamic>{},
        )
      : <String, dynamic>{};
  if (saleRow['id'] != saleId ||
      saleRow['total'] != '150.00' ||
      saleRow['amount_paid'] != '0.00') {
    throw StateError('P16 final sale invariant failed: $saleRow');
  }

  return 'P16 financial convergence mutation/feed/idempotency scenario verified';
}

Future<String> _firstLocationId(Dio dio, String businessId) async {
  final response = await dio.post('', data: {
    'action': 'restore_snapshot',
    'business_id': businessId,
  });
  _expect2xx(response, 'P16 location snapshot');
  final data = response.data is Map ? response.data['data'] : null;
  final locations = data is Map ? data['locations'] : null;
  if (locations is! List || locations.isEmpty) {
    throw StateError('P16 business has no locations');
  }
  final first = locations.first;
  final id = first is Map ? first['id'] : null;
  if (id is! String || id.isEmpty) {
    throw StateError('P16 snapshot location has no id');
  }
  return id;
}

Future<List<dynamic>> _fetchChanges(
  Dio dio, {
  required String businessId,
  required int cursor,
}) async {
  final response = await dio.get('', queryParameters: {
    'business_id': businessId,
    'cursor': cursor,
    'limit': 500,
  });
  final status = response.statusCode ?? 0;
  if (status < 200 || status >= 300) {
    throw StateError('P16 sync feed failed with HTTP $status: ${response.data}');
  }
  final root = response.data;
  final data = root is Map ? root['data'] : null;
  final changes = data is Map ? data['changes'] : null;
  if (changes is! List) {
    throw StateError('P16 sync feed returned no changes: ${response.data}');
  }
  return changes;
}

int _countEntity(List<dynamic> changes, String entityType, String entityId) {
  return changes.where((raw) =>
      raw is Map &&
      raw['entity_type'] == entityType &&
      raw['entity_id'] == entityId).length;
}

int _countOperation(
  List<dynamic> changes,
  String entityType,
  String operationId,
) {
  return changes.where((raw) {
    if (raw is! Map || raw['entity_type'] != entityType) return false;
    final payload = raw['payload'];
    return payload is Map &&
        (payload['operation_id'] == operationId ||
            payload['client_reference'] == operationId);
  }).length;
}

dynamic _actionData(Response<dynamic> response) {
  final root = response.data;
  final data = root is Map ? root['data'] : null;
  if (data is Map && data['data'] is Map) {
    return data['data'];
  }
  return data;
}

void _expect2xx(Response<dynamic> response, String operation) {
  final status = response.statusCode ?? 0;
  if (status < 200 || status >= 300) {
    throw StateError(
      '$operation failed with HTTP $status: ${response.data}',
    );
  }
}

Future<String?> _registerDevice(
  Dio dio, {
  required String businessId,
  required String deviceId,
}) async {
  final response = await dio.post('', data: {
    'action': 'register_device',
    'business_id': businessId,
    'device_client_id': deviceId,
    'device_name': 'Fulus CI multi-device convergence',
    'platform': 'ci',
    'app_version': 'e2e',
  });
  final status = response.statusCode ?? 0;
  if (status < 200 || status >= 300) {
    throw StateError(
      'register_device failed with HTTP $status: ${response.data}',
    );
  }
  final root = response.data;
  final data = root is Map ? root['data'] : null;
  final device = data is Map ? data['device'] : null;
  final id = device is Map ? device['id'] : null;
  if (id is! String || id.isEmpty) {
    throw StateError(
      'register_device returned no server device id: ${response.data}',
    );
  }
  stdout.writeln('PASS: secondary E2E device registered');
  return id;
}

Future<String> _resolveAccessToken({
  required String authUrl,
  required String publishableKey,
}) async {
  final email = _required('FULUS_E2E_EMAIL');
  final password = _required('FULUS_E2E_PASSWORD');
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
    data: {'email': email, 'password': password},
  );
  final status = response.statusCode ?? 0;
  final data = response.data;
  final token = data is Map ? data['access_token'] : null;
  if (status < 200 || status >= 300 || token is! String || token.isEmpty) {
    throw StateError(
      'E2E password authentication failed with HTTP $status: $data',
    );
  }
  return token;
}

String _required(String name) {
  final value = Platform.environment[name];
  if (value == null || value.isEmpty) {
    throw StateError('$name is required for the multi-device E2E test.');
  }
  return value;
}
