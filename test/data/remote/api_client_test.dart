import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:fulus_mobile/data/local/secure_storage/secure_storage.dart';
import 'package:fulus_mobile/data/remote/api_client.dart';

class MockSecureStorage extends Mock implements SecureStorage {}

Future<void> _json(
  HttpResponse response,
  int statusCode,
  Map<String, dynamic> body,
) async {
  response.statusCode = statusCode;
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(body));
  await response.close();
}

void main() {
  late HttpServer server;
  late MockSecureStorage storage;
  late String? storedRefreshToken;
  late int expiredCallbackCount;
  late ApiClient client;

  setUp(() async {
    storedRefreshToken = 'refresh-0';
    expiredCallbackCount = 0;
    storage = MockSecureStorage();

    when(() => storage.getRefreshToken())
        .thenAnswer((_) async => storedRefreshToken);
    when(() => storage.setRefreshToken(any())).thenAnswer((invocation) async {
      storedRefreshToken = invocation.positionalArguments.first as String;
    });
    when(() => storage.deleteRefreshToken()).thenAnswer((_) async {
      storedRefreshToken = null;
    });
    when(() => storage.getDeviceClientId()).thenAnswer((_) async => null);

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = ApiClient(
      baseUrl: 'http://127.0.0.1:${server.port}',
      secureStorage: storage,
      onSessionExpired: () async {
        expiredCallbackCount++;
      },
    );
    client.configureServerAuth(
      supabaseUrl: 'http://127.0.0.1:${server.port}',
      publishableKey: 'test-publishable-key',
    );
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('concurrent 401 responses perform exactly one refresh and persist rotation',
      () async {
    client.setAccessToken('expired-access');

    var protectedCalls = 0;
    var refreshCalls = 0;
    final refreshStarted = Completer<void>();
    final releaseRefresh = Completer<void>();

    server.listen((request) async {
      if (request.uri.path == '/auth/v1/token') {
        refreshCalls++;
        if (!refreshStarted.isCompleted) {
          refreshStarted.complete();
        }
        await releaseRefresh.future;
        await _json(request.response, 200, {
          'access_token': 'fresh-access',
          'refresh_token': 'refresh-1',
          'user': {'id': 'user-1'},
        });
        return;
      }

      if (request.uri.path == '/protected') {
        protectedCalls++;
        final authorization = request.headers.value('authorization');
        if (authorization == 'Bearer fresh-access') {
          await _json(request.response, 200, {'ok': true});
          return;
        }

        if (protectedCalls == 1) {
          await _json(request.response, 401, {
            'code': 'invalid_token',
            'message': 'expired',
          });
        } else {
          await refreshStarted.future;
          await _json(request.response, 401, {
            'code': 'invalid_token',
            'message': 'expired',
          });
        }
        return;
      }

      await _json(request.response, 404, {'message': 'not found'});
    });

    final first = client.dio.get<Map<String, dynamic>>('/protected');
    final second = client.dio.get<Map<String, dynamic>>('/protected');

    await refreshStarted.future;
    await Future<void>.delayed(Duration.zero);
    releaseRefresh.complete();

    final results = await Future.wait([first, second]);

    expect(results, hasLength(2));
    expect(results[0].data?['ok'], isTrue);
    expect(results[1].data?['ok'], isTrue);
    expect(refreshCalls, 1);
    expect(storedRefreshToken, 'refresh-1');
    expect(expiredCallbackCount, 0);
  });

  test('startup restore shares the in-flight refresh with a simultaneous 401',
      () async {
    client.setAccessToken(null);

    var refreshCalls = 0;
    final refreshStarted = Completer<void>();
    final releaseRefresh = Completer<void>();

    server.listen((request) async {
      if (request.uri.path == '/auth/v1/token') {
        refreshCalls++;
        refreshStarted.complete();
        await releaseRefresh.future;
        await _json(request.response, 200, {
          'access_token': 'fresh-access',
          'refresh_token': 'refresh-2',
          'user': {'id': 'user-1'},
        });
        return;
      }

      if (request.uri.path == '/protected') {
        await refreshStarted.future;
        await _json(request.response, 401, {
          'code': 'invalid_token',
          'message': 'expired',
        });
        return;
      }

      await _json(request.response, 404, {'message': 'not found'});
    });

    final restore = client.restoreServerSession(
      supabaseUrl: 'http://127.0.0.1:${server.port}',
      publishableKey: 'test-publishable-key',
    );
    await refreshStarted.future;

    final protectedRequest = client.dio.get<Map<String, dynamic>>('/protected');
    await Future<void>.delayed(Duration.zero);
    releaseRefresh.complete();

    final session = await restore;
    final response = await protectedRequest;

    expect(session?['access_token'], 'fresh-access');
    expect(response.data?['ok'], isTrue);
    expect(refreshCalls, 1);
    expect(storedRefreshToken, 'refresh-2');
    expect(expiredCallbackCount, 0);
  });

  test('transient refresh server failure preserves the durable refresh token',
      () async {
    client.setAccessToken('expired-access');

    var refreshCalls = 0;
    server.listen((request) async {
      if (request.uri.path == '/auth/v1/token') {
        refreshCalls++;
        await _json(request.response, 500, {
          'code': 'temporarily_unavailable',
          'message': 'retry later',
        });
        return;
      }

      if (request.uri.path == '/protected') {
        await _json(request.response, 401, {
          'code': 'invalid_token',
          'message': 'expired',
        });
        return;
      }

      await _json(request.response, 404, {'message': 'not found'});
    });

    await expectLater(
      client.dio.get('/protected'),
      throwsA(isA<DioException>()),
    );

    expect(refreshCalls, 1);
    expect(storedRefreshToken, 'refresh-0');
    expect(expiredCallbackCount, 0);
  });

  test('explicitly rejected refresh token expires the cloud session',
      () async {
    client.setAccessToken('expired-access');

    server.listen((request) async {
      if (request.uri.path == '/auth/v1/token') {
        await _json(request.response, 400, {
          'code': 'refresh_token_not_found',
          'message': 'refresh token is invalid',
        });
        return;
      }

      if (request.uri.path == '/protected') {
        await _json(request.response, 401, {
          'code': 'invalid_token',
          'message': 'expired',
        });
        return;
      }

      await _json(request.response, 404, {'message': 'not found'});
    });

    await expectLater(
      client.dio.get('/protected'),
      throwsA(isA<DioException>()),
    );

    expect(storedRefreshToken, isNull);
    expect(expiredCallbackCount, 1);
  });
}
