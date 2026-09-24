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
