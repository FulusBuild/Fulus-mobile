import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:fulus_mobile/data/local/secure_storage/secure_storage.dart';
import 'package:fulus_mobile/data/remote/api_client.dart';
import 'package:fulus_mobile/data/remote/fulus_staff_access_api.dart';

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
      baseUrl: 'http://127.0.0.1:${server.port}',
      secureStorage: storage,
      onSessionExpired: () async {},
      enableGenericRetry: false,
    );
  });

  tearDown(() => server.close(force: true));

  test('ownership review calls use fulus-api by default', () async {
    final requestedPath = Completer<String>();
    server.listen((request) async {
      requestedPath.complete(request.uri.path);
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'data': {'items': <dynamic>[]},
      }));
      await request.response.close();
    });

    final api = FulusStaffAccessApi(
      client: client,
      functionBaseUrl:
          'http://127.0.0.1:${server.port}/functions/v1/fulus-staff-api',
    );

    final reviews = await api.listLocationOwnershipReviews(
      businessId: 'business-1',
    );

    expect(reviews, isEmpty);
    expect(await requestedPath.future, '/functions/v1/fulus-api');
  });

  test('ownership review endpoint can be explicitly overridden', () async {
    final requestedPath = Completer<String>();
    server.listen((request) async {
      requestedPath.complete(request.uri.path);
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'data': {'items': <dynamic>[]},
      }));
      await request.response.close();
    });

    final api = FulusStaffAccessApi(
      client: client,
      functionBaseUrl:
          'http://127.0.0.1:${server.port}/functions/v1/fulus-staff-api',
      ownershipFunctionBaseUrl:
          'http://127.0.0.1:${server.port}/functions/v1/custom-ownership-api',
    );

    await api.listLocationOwnershipReviews(businessId: 'business-1');

    expect(await requestedPath.future, '/functions/v1/custom-ownership-api');
  });
}
