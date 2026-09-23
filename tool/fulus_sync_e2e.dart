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
  final ephemeralDeviceIds = <String>[];

  try {
    final preflight = await _preflightDevice(dio, businessId: businessId);
    if (preflight == _PreflightResult.cursorTooOld) {
      await _verifyAuthoritativeRecoverySnapshot(
        dio,
        businessId: businessId,
      );
      stdout.writeln('PASS: authoritative restore snapshot exposes a valid recovery boundary');
      final freshDeviceId = 'e2e-${suffix.replaceAll(RegExp(r'[^a-zA-Z0-9-]'), '')}';
      final freshServerDeviceId = await _registerEphemeralDevice(dio, businessId: businessId, deviceClientId: freshDeviceId);
      if (freshServerDeviceId != null) ephemeralDeviceIds.add(freshServerDeviceId);
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

    final categoryOperationId = 'e2e-category-$suffix';
    final categoryResponse = await _submitCatalog(
      dio,
      businessId: businessId,
      action: 'catalog_upsert',
      entity: 'categories',
      operationId: categoryOperationId,
      item: {
        'name': 'Fulus E2E Category $suffix',
        'description': 'Cloud Sync V1 category contract',
      },
    );
    _expect2xx(categoryResponse, 'category.create');
    final categoryId = _entityId(categoryResponse);
    if (categoryId == null || categoryId.isEmpty) {
      throw StateError('category.create returned no server entity ID: ${categoryResponse.data}');
    }
    stdout.writeln('PASS: category.create');

    final supplierOperationId = 'e2e-supplier-$suffix';
    final supplierResponse = await _submitCatalog(
      dio,
      businessId: businessId,
      action: 'catalog_upsert',
      entity: 'suppliers',
      operationId: supplierOperationId,
      item: {
        'name': 'Fulus E2E Supplier $suffix',
        'phone': '08000000002',
        'email': null,
        'address': 'Cloud Sync V1 supplier contract',
      },
    );
    _expect2xx(supplierResponse, 'supplier.create');
    final supplierId = _entityId(supplierResponse);
    if (supplierId == null || supplierId.isEmpty) {
      throw StateError('supplier.create returned no server entity ID: ${supplierResponse.data}');
    }
    stdout.writeln('PASS: supplier.create');

    final createPayload = {
      'name': 'Fulus E2E Test Product $suffix',
      'sku': sku,
      'cost_price': 100,
      'selling_price': 150,
      'low_stock_threshold': 5,
      'is_active': true,
      'category_id': categoryId,
      'supplier_id': supplierId,
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

    // The idempotency key is business-scoped for storage, but its meaning is
    // device-scoped. Reusing the same operation from another registered device
    // must never replay the first device's result.
    final firstDeviceClientId = dio.options.headers['x-fulus-device-id']?.toString();
    if (firstDeviceClientId == null || firstDeviceClientId.isEmpty) {
      throw StateError('E2E lost the active device identity before idempotency scope verification.');
    }
    final secondDeviceClientId =
        'e2e-scope-${suffix.replaceAll(RegExp(r'[^a-zA-Z0-9-]'), '')}';
    final secondServerDeviceId = await _registerEphemeralDevice(
      dio,
      businessId: businessId,
      deviceClientId: secondDeviceClientId,
    );
    if (secondServerDeviceId != null) ephemeralDeviceIds.add(secondServerDeviceId);
    dio.options.headers['x-fulus-device-id'] = secondDeviceClientId;
    final crossDeviceReplay = await _submitCatalog(
      dio,
      businessId: businessId,
      action: 'catalog_upsert',
      entity: 'products',
      operationId: createOperationId,
      item: createPayload,
    );
    final crossDeviceStatus = crossDeviceReplay.statusCode ?? 0;
    final crossDeviceCode = crossDeviceReplay.data is Map &&
            (crossDeviceReplay.data as Map)['error'] is Map
        ? ((crossDeviceReplay.data as Map)['error'] as Map)['code']
        : null;
    if (crossDeviceStatus != 409 || crossDeviceCode != 'IDEMPOTENCY_CONFLICT') {
      throw StateError(
        'Expected cross-device idempotency rejection, got HTTP '
        '$crossDeviceStatus: ${crossDeviceReplay.data}',
      );
    }
    final locationOperationId = '${createOperationId}-location-scope';
    dio.options.headers['x-fulus-device-id'] = firstDeviceClientId;
    final locationCreate = await dio.post(
      '',
      data: {
        'action': 'location_create',
        'business_id': businessId,
        'operation_id': locationOperationId,
        'name': 'E2E Sync Scope ${suffix}',
        'code': 'E2E-SCOPE-${suffix}',
        'address': 'E2E rollback-compatible location',
        'timezone': 'Africa/Lagos',
      },
    );
    if ((locationCreate.statusCode ?? 0) < 200 ||
        (locationCreate.statusCode ?? 0) >= 300) {
      throw StateError(
        'Initial location idempotency scope probe failed: ${locationCreate.data}',
      );
    }

    final locationCreateData = locationCreate.data is Map
        ? (locationCreate.data as Map)['data']
        : null;
    final locationCreateResult = locationCreateData is Map
        ? locationCreateData
        : locationCreate.data is Map
            ? locationCreate.data as Map
            : null;
    final firstLocationId = locationCreateResult?['location_id'];
    if (firstLocationId is! String || firstLocationId.isEmpty) {
      throw StateError(
        'Location create did not return a server location id: ${locationCreate.data}',
      );
    }

    final locationSameDeviceReplay = await dio.post(
      '',
      data: {
        'action': 'location_create',
        'business_id': businessId,
        'operation_id': locationOperationId,
        'name': 'E2E Sync Scope ${suffix}',
        'code': 'E2E-SCOPE-${suffix}',
        'address': 'E2E rollback-compatible location',
        'timezone': 'Africa/Lagos',
      },
    );
    if ((locationSameDeviceReplay.statusCode ?? 0) != 200) {
      throw StateError(
        'Expected same-device location idempotent replay, got HTTP '
        '${locationSameDeviceReplay.statusCode}: ${locationSameDeviceReplay.data}',
      );
    }
    final replayData = locationSameDeviceReplay.data is Map
        ? (locationSameDeviceReplay.data as Map)['data']
        : null;
    final replayResult = replayData is Map
        ? replayData
        : locationSameDeviceReplay.data is Map
            ? locationSameDeviceReplay.data as Map
            : null;
    if (replayResult?['location_id'] != firstLocationId) {
      throw StateError(
        'Same-device location replay returned a different location: '
        '${locationSameDeviceReplay.data}',
      );
    }

    final locationDifferentRequest = await dio.post(
      '',
      data: {
        'action': 'location_create',
        'business_id': businessId,
        'operation_id': locationOperationId,
        'name': 'E2E Sync Scope ${suffix} DIFFERENT',
        'code': 'E2E-SCOPE-${suffix}-DIFFERENT',
        'address': 'E2E different request',
        'timezone': 'Africa/Lagos',
      },
    );
    if (locationDifferentRequest.statusCode != 409 ||
        locationDifferentRequest.data is! Map ||
        (locationDifferentRequest.data as Map)['error'] is! Map ||
        ((locationDifferentRequest.data as Map)['error'] as Map)['code'] !=
            'IDEMPOTENCY_CONFLICT') {
      throw StateError(
        'Expected same-device location request conflict, got HTTP '
        '${locationDifferentRequest.statusCode}: ${locationDifferentRequest.data}',
      );
    }

    dio.options.headers['x-fulus-device-id'] = secondDeviceClientId;
    final locationReplay = await dio.post(
      '',
      data: {
        'action': 'location_create',
        'business_id': businessId,
        'operation_id': locationOperationId,
        'name': 'E2E Sync Scope ${suffix}',
        'code': 'E2E-SCOPE-${suffix}',
        'address': 'E2E rollback-compatible location',
        'timezone': 'Africa/Lagos',
      },
    );
    if (locationReplay.statusCode != 409 ||
        locationReplay.data is! Map ||
        (locationReplay.data as Map)['error'] is! Map ||
        ((locationReplay.data as Map)['error'] as Map)['code'] !=
            'IDEMPOTENCY_CONFLICT') {
      throw StateError(
        'Expected cross-device location idempotency rejection, got HTTP '
        '${locationReplay.statusCode}: ${locationReplay.data}',
      );
    }

    dio.options.headers['x-fulus-device-id'] = firstDeviceClientId;
    stdout.writeln('PASS: idempotency keys cannot cross device scope');

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


    // Live mutation-matrix probes for commands that previously lacked
    // production contract coverage in this E2E.
    final customerOperationId = 'e2e-customer-' + suffix;
    final customerResponse = await dio.post('', data: {
      'action': 'customer_create',
      'business_id': businessId,
      'operation_id': customerOperationId,
      'name': 'Fulus E2E Customer ' + suffix,
      'phone': '08000000000',
      'credit_limit': 100000,
      'notes': 'Cloud Sync V1 mutation matrix',
    });
    _expect2xx(customerResponse, 'customer.create');
    final customerData = _actionData(customerResponse);
    final customerId = customerData?['customer_id'];
    if (customerId is! String || customerId.isEmpty) {
      throw StateError('customer.create returned no customer_id: ' + customerResponse.data.toString());
    }
    stdout.writeln('PASS: customer.create');

    final creditSaleOperationId = 'e2e-credit-sale-' + suffix;
    final creditSale = await dio.post('', data: {
      'action': 'sale_create',
      'business_id': businessId,
      'operation_id': creditSaleOperationId,
      'client_reference': creditSaleOperationId,
      'location_id': e2eLocationId,
      'customer_id': customerId,
      'sale_date': DateTime.now().toUtc().toIso8601String(),
      'discount': 0,
      'tax': 0,
      'amount_paid': 0,
      'payment_method': 'credit',
      'notes': 'Cloud Sync V1 mutation matrix credit sale',
      'items': [
        {
          'product_id': serverId,
          'description': 'E2E mutation matrix product',
          'quantity': 1,
          'unit_price': 150,
          'cost_price_at_sale': 100,
        },
      ],
    });
    _expect2xx(creditSale, 'sale.create credit mutation matrix');
    final creditSaleData = _actionData(creditSale);
    final creditSaleId = creditSaleData?['sale_id'];
    if (creditSaleId is! String || creditSaleId.isEmpty) {
      throw StateError('credit sale returned no sale_id: ' + creditSale.data.toString());
    }
    stdout.writeln('PASS: sale.create credit mutation matrix');

    final salePayment = await dio.post('', data: {
      'action': 'sale_payment',
      'business_id': businessId,
      'operation_id': 'e2e-sale-payment-' + suffix,
      'sale_id': creditSaleId,
      'amount': 50,
      'payment_method': 'cash',
    });
    _expect2xx(salePayment, 'sale.payment');
    stdout.writeln('PASS: sale.payment');

    final repayment = await dio.post('', data: {
      'action': 'customer_repayment',
      'business_id': businessId,
      'operation_id': 'e2e-repayment-' + suffix,
      'customer_id': customerId,
      'amount': 50,
      'payment_method': 'cash',
      'note': 'Cloud Sync V1 mutation matrix repayment',
    });
    _expect2xx(repayment, 'customer.repayment');
    stdout.writeln('PASS: customer.repayment');

    final returnResponse = await dio.post('', data: {
      'action': 'return_create',
      'business_id': businessId,
      'operation_id': 'e2e-return-' + suffix,
      'sale_id': creditSaleId,
      'reason': 'Cloud Sync V1 mutation matrix return',
      'refund_amount': 0,
      'items': [
        {'product_id': serverId, 'quantity': 1},
      ],
    });
    _expect2xx(returnResponse, 'return.create');
    stdout.writeln('PASS: return.create');

    final customerUpdate = await dio.post('', data: {
      'action': 'customer_update',
      'business_id': businessId,
      'operation_id': 'e2e-customer-update-' + suffix,
      'payload': {
        'server_id': customerId,
        'name': 'Fulus E2E Customer Updated ' + suffix,
        'phone': '08000000000',
        'credit_limit': 125000,
        'notes': 'Cloud Sync V1 customer update',
        'is_active': true,
      },
    });
    _expect2xx(customerUpdate, 'customer.update');
    stdout.writeln('PASS: customer.update');

    final expenseCategoryResponse = await dio.post('', data: {
      'action': 'expense_category_create',
      'business_id': businessId,
      'operation_id': 'e2e-expense-category-' + suffix,
      'payload': {'name': 'E2E Category ' + suffix},
    });
    _expect2xx(expenseCategoryResponse, 'expense_category.create');
    stdout.writeln('PASS: expense_category.create');

    final expenseResponse = await dio.post('', data: {
      'action': 'expense_create',
      'business_id': businessId,
      'operation_id': 'e2e-expense-' + suffix,
      'location_id': e2eLocationId,
      'amount': 25,
      'category': 'E2E Category ' + suffix,
      'description': 'Cloud Sync V1 mutation matrix expense',
      'expense_date': DateTime.now().toUtc().toIso8601String(),
      'payment_method': 'cash',
    });
    _expect2xx(expenseResponse, 'expense.create');
    final expenseData = _actionData(expenseResponse);
    final expenseId = expenseData?['expense_id'] ?? expenseData?['id'];
    if (expenseId is! String || expenseId.isEmpty) {
      throw StateError('expense.create returned no expense id: ' + expenseResponse.data.toString());
    }
    stdout.writeln('PASS: expense.create');

    final expenseUpdate = await dio.post('', data: {
      'action': 'expense_update',
      'business_id': businessId,
      'operation_id': 'e2e-expense-update-' + suffix,
      'payload': {
        'server_id': expenseId,
        'location_id': e2eLocationId,
        'amount': 30,
        'category': 'E2E Category ' + suffix,
        'description': 'Cloud Sync V1 mutation matrix expense updated',
        'expense_date': DateTime.now().toUtc().toIso8601String(),
        'payment_method': 'cash',
      },
    });
    _expect2xx(expenseUpdate, 'expense.update');
    stdout.writeln('PASS: expense.update');

    final inventoryAdjust = await dio.post('', data: {
      'action': 'inventory_adjust',
      'business_id': businessId,
      'operation_id': 'e2e-inventory-adjust-' + suffix,
      'product_id': serverId,
      'location_id': e2eLocationId,
      'quantity_delta': 2,
      'reason': 'Cloud Sync V1 mutation matrix adjustment',
    });
    _expect2xx(inventoryAdjust, 'inventory.adjust');
    stdout.writeln('PASS: inventory.adjust');

    final drawerOpen = await dio.post('', data: {
      'action': 'cash_drawer_open',
      'business_id': businessId,
      'operation_id': 'e2e-drawer-open-' + suffix,
      'location_id': firstLocationId,
      'opening_cash': 1000,
      'opened_at': DateTime.now().toUtc().toIso8601String(),
    });
    _expect2xx(drawerOpen, 'cash_drawer.open');
    final drawerData = _actionData(drawerOpen);
    final shiftId = drawerData?['shift_id'] ?? drawerData?['id'];
    if (shiftId is! String || shiftId.isEmpty) {
      throw StateError('cash_drawer.open returned no shift id: ' + drawerOpen.data.toString());
    }
    stdout.writeln('PASS: cash_drawer.open');

    final drawerClose = await dio.post('', data: {
      'action': 'cash_drawer_close',
      'business_id': businessId,
      'operation_id': 'e2e-drawer-close-' + suffix,
      'shift_id': shiftId,
      'closing_cash': 1000,
      'cash_difference': 0,
      'closing_note': 'Cloud Sync V1 mutation matrix close',
      'closed_at': DateTime.now().toUtc().toIso8601String(),
    });
    _expect2xx(drawerClose, 'cash_drawer.close');
    stdout.writeln('PASS: cash_drawer.close');

    final productChangeSequence = await _findChangeSequence(
      dio,
      businessId: businessId,
      entityType: 'product',
      entityId: serverId,
    );

    // Regression for the real-device failure: every stock movement change
    // must carry replayable timestamps. The server migration now enriches
    // both new and retained events from inventory_movements.created_at.
    final stockTimestampProbe = await dio.get(
      '',
      queryParameters: {
        'business_id': businessId,
        'cursor': max(0, productChangeSequence - 1),
        'limit': 500,
      },
    );
    _expect2xx(stockTimestampProbe, 'stock movement timestamp contract');
    final probeRoot = stockTimestampProbe.data;
    final probeData = probeRoot is Map ? probeRoot['data'] : null;
    final probeChanges = probeData is Map ? probeData['changes'] : null;
    if (probeChanges is! List) {
      throw StateError('Stock movement timestamp probe returned no change list.');
    }
    final stockMovementChanges = probeChanges.where((raw) {
      if (raw is! Map || raw['entity_type'] != 'stock_movement') return false;
      final payload = raw['payload'];
      return payload is Map && payload['product_id'] == serverId;
    }).toList(growable: false);
    if (stockMovementChanges.isEmpty) {
      throw StateError(
        'No stock movement change was emitted for the product initial-stock mutation.',
      );
    }
    for (final raw in stockMovementChanges) {
      final payload = (raw as Map)['payload'];
      if (payload is! Map ||
          payload['created_at'] is! String ||
          DateTime.tryParse(payload['created_at'] as String) == null ||
          payload['updated_at'] is! String ||
          DateTime.tryParse(payload['updated_at'] as String) == null) {
        throw StateError(
          'Stock movement change is missing valid created_at/updated_at timestamps: $raw',
        );
      }
    }
    stdout.writeln('PASS: stock movement change feed carries valid timestamps');

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

    // Tombstone race: delete on device A, then prove device B cannot
    // resurrect its stale local copy with a pre-delete cursor.
    final preDeleteSequence = await _findChangeSequence(
      dio,
      businessId: businessId,
      entityType: 'product',
      entityId: serverId,
    );
    if (preDeleteSequence <= 0) {
      throw StateError('Unable to establish the product cursor before tombstone test.');
    }

    final delete = await _submitCatalog(
      dio,
      businessId: businessId,
      action: 'catalog_delete',
      entity: 'products',
      operationId: deleteOperationId,
      id: serverId,
      baseCursor: preDeleteSequence,
    );
    _expect2xx(delete, 'cleanup product.delete');

    dio.options.headers['x-fulus-device-id'] = secondDeviceClientId;
    final staleResurrection = await _submitCatalog(
      dio,
      businessId: businessId,
      action: 'catalog_upsert',
      entity: 'products',
      operationId: 'e2e-tombstone-resurrection-' + suffix,
      baseCursor: preDeleteSequence,
      id: serverId,
      item: {
        ...createPayload,
        'name': 'Fulus E2E forbidden resurrection ' + suffix,
      },
    );
    final resurrectionStatus = staleResurrection.statusCode ?? 0;
    final resurrectionError = staleResurrection.data is Map
        ? (staleResurrection.data as Map)['error']
        : null;
    final resurrectionCode = resurrectionError is Map
        ? resurrectionError['code']
        : null;
    if (resurrectionStatus != 409 || resurrectionCode != 'SYNC_CONFLICT') {
      throw StateError(
        'Expected stale post-delete update to be rejected as SYNC_CONFLICT, '
        'got HTTP ' + resurrectionStatus.toString() + ': ' + staleResurrection.data.toString(),
      );
    }

    final canonicalAfterDelete = await dio.get(
      _canonicalStateUrl(),
      queryParameters: {
        'business_id': businessId,
        'entity_type': 'product',
        'entity_id': serverId,
      },
    );
    _expect2xx(canonicalAfterDelete, 'canonical product tombstone read');
    final canonicalRoot = canonicalAfterDelete.data;
    final canonicalData = canonicalRoot is Map ? canonicalRoot['data'] : null;
    final canonicalRow = canonicalData is Map ? canonicalData['product'] : null;
    if (canonicalData is! Map ||
        canonicalData['operation'] != 'upsert' ||
        canonicalRow is! Map ||
        canonicalRow['deleted_at'] == null) {
      throw StateError(
        'Canonical product tombstone was not preserved: ' + canonicalAfterDelete.data.toString(),
      );
    }

    // Revocation must take effect at the API authorization boundary, not
    // merely in the device-management UI. Revoke the second ephemeral device
    // while the primary device remains authorized, then prove that a request
    // carrying the revoked device identity is rejected before command handling.
    await _revokeEphemeralDevice(
      authUrl: _required('FULUS_AUTH_URL'),
      publishableKey: _required('FULUS_PUBLISHABLE_KEY'),
      accessToken: token,
      businessId: businessId,
      deviceId: secondServerDeviceId,
    );
    dio.options.headers['x-fulus-device-id'] = secondDeviceClientId;
    final revokedProbe = await dio.post('', data: {
      'action': 'sync_operation',
      'business_id': businessId,
      'operation_id': 'e2e-revoked-device-${DateTime.now().microsecondsSinceEpoch}',
      'operation_type': 'revocation_probe',
      'payload': <String, dynamic>{},
    });
    if ((revokedProbe.statusCode ?? 0) != 403) {
      throw StateError(
        'Revoked device was not rejected at the API boundary: '
        '${revokedProbe.statusCode}: ${revokedProbe.data}',
      );
    }
    cleanedUp = true;
    dio.options.headers['x-fulus-device-id'] = firstDeviceClientId;
    stdout.writeln('PASS: revoked device rejected before sync command execution');
    stdout.writeln('PASS: delete tombstone blocks stale resurrection and canonical state remains deleted');
  } finally {
    for (final deviceId in ephemeralDeviceIds) {
      try {
        await _revokeEphemeralDevice(
          authUrl: _required('FULUS_AUTH_URL'),
          publishableKey: _required('FULUS_PUBLISHABLE_KEY'),
          accessToken: token,
          businessId: businessId,
          deviceId: deviceId,
        );
        stdout.writeln('PASS: ephemeral E2E device revoked');
      } catch (error) {
        stderr.writeln(
          'WARNING: automatic cleanup failed for ephemeral E2E device: $error',
        );
      }
    }
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

String _canonicalStateUrl() {
  final apiUrl = _required('FULUS_API_URL');
  return apiUrl.replaceFirst(RegExp(r'/fulus-api/?$'), '/fulus-sync-state');
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
  var latestSequence = 0;
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
        if (sequence is num) {
          final value = sequence.toInt();
          // The conflict check rejects any entity change strictly newer than
          // base_cursor. Keep scanning the full retained feed so callers get
          // the entity's latest change, not its first historical change.
          latestSequence = max(latestSequence, value);
        }
      }
    }
    final next = data['next_cursor'];
    final hasMore = data['has_more'] == true;
    if (!hasMore || next is! num || next.toInt() <= cursor) break;
    cursor = next.toInt();
  }
  if (latestSequence > 0) return latestSequence;
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

Future<String?> _registerEphemeralDevice(
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
  final root = response.data;
  final data = root is Map ? root['data'] : null;
  final device = data is Map ? data['device'] : null;
  final serverId = device is Map && device['id'] is String
      ? device['id'] as String
      : null;
  stdout.writeln('PASS: ephemeral E2E device registered');
  return serverId;
}

Future<void> _revokeEphemeralDevice({
  required String authUrl,
  required String publishableKey,
  required String accessToken,
  required String businessId,
  required String deviceId,
}) async {
  final dio = Dio(BaseOptions(
    baseUrl: _required('FULUS_API_URL'),
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    headers: {
      'apikey': publishableKey,
      'Authorization': 'Bearer $accessToken',
      'content-type': 'application/json',
      'x-fulus-device-id': _required('FULUS_DEVICE_ID'),
    },
    validateStatus: (_) => true,
  ));
  final response = await dio.post('', data: {
    'action': 'revoke_own_device',
    'business_id': businessId,
    'device_id': deviceId,
  });
  _expect2xx(response, 'revoke ephemeral E2E device');
}


String _required(String name) {
  final value = Platform.environment[name];
  if (value == null || value.isEmpty) {
    throw StateError('$name is required for the Fulus E2E contract test.');
  }
  return value;
}

Map<String, dynamic>? _actionData(Response<dynamic> response) {
  final root = response.data;
  if (root is! Map) return null;
  final outer = root['data'];
  if (outer is! Map) return null;
  final nested = outer['data'];
  if (nested is Map) {
    return Map<String, dynamic>.from(nested);
  }
  return Map<String, dynamic>.from(outer);
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
