import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:fulus_mobile/core/errors/failure.dart';
import 'package:fulus_mobile/data/local/secure_storage/secure_storage.dart';
import 'package:fulus_mobile/data/remote/api_client.dart';
import 'package:fulus_mobile/data/remote/endpoints/auth_api.dart';

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
  late ApiClient client;
  late AuthApi authApi;

  setUp(() async {
    storage = MockSecureStorage();
    when(() => storage.getRefreshToken()).thenAnswer((_) async => null);
    when(() => storage.getDeviceClientId()).thenAnswer((_) async => null);
    when(() => storage.setRefreshToken(any())).thenAnswer((_) async {});
    when(() => storage.deleteRefreshToken()).thenAnswer((_) async {});

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = ApiClient(
      baseUrl: 'http://127.0.0.1:${server.port}',
      secureStorage: storage,
      onSessionExpired: () async {},
    );
    authApi = AuthApi(client);
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('signup 5xx is reported as an account-creation failure, not cloud backup failure',
      () async {
    server.listen((request) async {
      expect(request.uri.path, '/auth/v1/signup');
      await _json(request.response, 500, {
        'code': 'unexpected_failure',
        'msg': 'SMTP provider rejected credentials',
      });
    });

    expect(
      () => authApi.signUpServer(
        email: 'new@example.com',
        password: 'StrongPassword!123',
        supabaseUrl: 'http://127.0.0.1:${server.port}',
        publishableKey: 'test-publishable-key',
      ),
      throwsA(
        isA<BusinessRuleFailure>()
            .having((failure) => failure.code, 'code', 'AUTH_SIGNUP_UNAVAILABLE')
            .having(
              (failure) => failure.message,
              'message',
              'Account creation is temporarily unavailable. Please try again in a moment.',
            ),
      ),
    );
  });
}
