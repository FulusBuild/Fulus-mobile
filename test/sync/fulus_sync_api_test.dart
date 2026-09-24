import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:fulus_mobile/data/local/secure_storage/secure_storage.dart';
import 'package:fulus_mobile/data/remote/api_client.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';
import 'package:fulus_mobile/sync/sync_error.dart';
import 'package:fulus_mobile/core/errors/failure.dart';

class _MockSecureStorage extends Mock implements SecureStorage {}

void main() {
  late HttpServer server;
  late ApiClient client;

  setUp(() async {
    final storage = _MockSecureStorage();
    when(() => storage.getRefreshToken()).thenAnswer((_) async => null);
    when(() => storage.getDeviceClientId()).thenAnswer((_) async => null);
    when(() => storage.setRefreshToken(any())).thenAnswer((_) async {});
    when(() => storage.deleteRefreshToken()).thenAnswer((_) async {});

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = ApiClient(
      baseUrl: 'http://127.0.0.1:' + server.port.toString(),
      secureStorage: storage,
      onSessionExpired: () async {},
      enableGenericRetry: false,
    );
  });

  tearDown(() => server.close(force: true));

  Future<void> respond(int statusCode, Map<String, dynamic> body) async {
    server.listen((request) async {
      request.response.statusCode = statusCode;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(body));
      await request.response.close();
    });
  }

  test('HTTP 429 from the sync transport is retryable instead of blocked',
      () async {
    final syncApi = FulusSyncApi(
      client: client,
      functionBaseUrl: 'http://127.0.0.1:' + server.port.toString() + '/fulus',
    );
    await respond(429, {
      'error': {
        'code': 'over_request_rate_limit',
        'message': 'Too many requests',
      },
    });

    await expectLater(
      syncApi.pullChanges(businessId: 'business-1', cursor: 10),
      throwsA(
        isA<SyncFailure>()
            .having((e) => e.kind, 'kind', SyncErrorKind.temporaryServer)
            .having((e) => e.shouldRetry, 'shouldRetry', true),
      ),
    );
  });

  test('HTTP 408 request timeout is retryable', () async {
    final syncApi = FulusSyncApi(
      client: client,
      functionBaseUrl: 'http://127.0.0.1:' + server.port.toString() + '/fulus',
    );
    await respond(408, {'message': 'request timed out'});

    await expectLater(
      syncApi.pullChanges(businessId: 'business-1', cursor: 10),
      throwsA(
        isA<SyncFailure>()
            .having((e) => e.kind, 'kind', SyncErrorKind.temporaryServer)
            .having((e) => e.shouldRetry, 'shouldRetry', true),
      ),
    );
  });

  test('HTTP 500 remains classified as an unavailable network/server error',
      () async {
    final syncApi = FulusSyncApi(
      client: client,
      functionBaseUrl: 'http://127.0.0.1:' + server.port.toString() + '/fulus',
    );
    await respond(500, {
      'error': {
        'code': 'server_error',
        'message': 'temporary failure',
      },
    });

    await expectLater(
      syncApi.pullChanges(businessId: 'business-1', cursor: 10),
      throwsA(isA<NetworkFailure>()),
    );
  });
}
