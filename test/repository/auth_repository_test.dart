import 'package:bms_mobile/core/errors/failure.dart';
import 'package:bms_mobile/data/local/secure_storage/secure_storage.dart';
import 'package:bms_mobile/data/remote/api_client.dart';
import 'package:bms_mobile/data/remote/endpoints/auth_api.dart';
import 'package:bms_mobile/data/repositories/auth_repository_impl.dart';
import 'package:bms_mobile/domain/entities/auth_user.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthApi extends Mock implements AuthApi {}

class MockApiClient extends Mock implements ApiClient {}

class MockSecureStorage extends Mock implements SecureStorage {}

void main() {
  late MockAuthApi authApi;
  late MockApiClient apiClient;
  late MockSecureStorage secureStorage;
  late AuthRepositoryImpl repository;

  const user = UserDto(
    id: 'user-1',
    username: 'owner',
    email: 'owner@example.com',
    fullName: 'Test Owner',
    role: 'admin',
    isActive: true,
  );
  const tokenResponse = TokenResponseDto(
    accessToken: 'access-1',
    refreshToken: 'refresh-1',
    tokenType: 'bearer',
    user: user,
  );

  setUp(() {
    authApi = MockAuthApi();
    apiClient = MockApiClient();
    secureStorage = MockSecureStorage();
    repository = AuthRepositoryImpl(
      authApi: authApi,
      apiClient: apiClient,
      secureStorage: secureStorage,
    );

    // Stub every mock call this repository might make with a harmless
    // default so tests only need to override what they actually care
    // about.
    when(() => apiClient.setAccessToken(any())).thenReturn(null);
    when(() => secureStorage.setRefreshToken(any())).thenAnswer((_) async {});
    when(() => secureStorage.deleteRefreshToken()).thenAnswer((_) async {});
  });

  group('login', () {
    test('sets the access token, stores the refresh token, and returns the user',
        () async {
      when(() => authApi.login(username: 'owner', password: 'secret1'))
          .thenAnswer((_) async => tokenResponse);

      final result = await repository.login(username: 'owner', password: 'secret1');

      expect(result.username, 'owner');
      expect(result.role, 'admin');
      expect(repository.currentUser?.id, 'user-1');
      verify(() => apiClient.setAccessToken('access-1')).called(1);
      verify(() => secureStorage.setRefreshToken('refresh-1')).called(1);
    });

    test('propagates invalidCredentials and leaves no session behind', () async {
      when(() => authApi.login(username: 'owner', password: 'wrong'))
          .thenThrow(const AuthFailure.invalidCredentials());

      await expectLater(
        repository.login(username: 'owner', password: 'wrong'),
        throwsA(isA<AuthFailure>()),
      );

      expect(repository.currentUser, isNull);
      verifyNever(() => apiClient.setAccessToken(any()));
      verifyNever(() => secureStorage.setRefreshToken(any()));
    });
  });

  group('restoreSession', () {
    test('returns null without calling the API when there is no stored token',
        () async {
      when(() => secureStorage.getRefreshToken()).thenAnswer((_) async => null);

      final result = await repository.restoreSession();

      expect(result, isNull);
      verifyNever(() => authApi.refresh(refreshToken: any(named: 'refreshToken')));
    });

    test('restores the session on a successful refresh', () async {
      when(() => secureStorage.getRefreshToken())
          .thenAnswer((_) async => 'stored-refresh');
      when(() => authApi.refresh(refreshToken: 'stored-refresh'))
          .thenAnswer((_) async => tokenResponse);

      final result = await repository.restoreSession();

      expect(result?.id, 'user-1');
      expect(repository.currentUser?.id, 'user-1');
      verify(() => apiClient.setAccessToken('access-1')).called(1);
    });

    test(
        'clears the stored refresh token when the server confirms it is '
        'genuinely invalid', () async {
      when(() => secureStorage.getRefreshToken())
          .thenAnswer((_) async => 'stale-refresh');
      when(() => authApi.refresh(refreshToken: 'stale-refresh'))
          .thenThrow(const AuthFailure.sessionExpired());

      final result = await repository.restoreSession();

      expect(result, isNull);
      verify(() => secureStorage.deleteRefreshToken()).called(1);
    });

    test(
        'does NOT clear the stored refresh token on a network failure — '
        'the token itself might still be perfectly valid', () async {
      when(() => secureStorage.getRefreshToken())
          .thenAnswer((_) async => 'still-good-refresh');
      when(() => authApi.refresh(refreshToken: 'still-good-refresh'))
          .thenThrow(const NetworkFailure.offline());

      final result = await repository.restoreSession();

      expect(result, isNull);
      verifyNever(() => secureStorage.deleteRefreshToken());
    });
  });

  group('logout', () {
    test('clears the local session even when the backend call fails',
        () async {
      when(() => authApi.login(username: 'owner', password: 'secret1'))
          .thenAnswer((_) async => tokenResponse);
      await repository.login(username: 'owner', password: 'secret1');

      when(() => authApi.logout()).thenThrow(Exception('network blip'));

      await repository.logout();

      expect(repository.currentUser, isNull);
      verify(() => apiClient.setAccessToken(null)).called(1);
      verify(() => secureStorage.deleteRefreshToken()).called(1);
    });
  });
}
