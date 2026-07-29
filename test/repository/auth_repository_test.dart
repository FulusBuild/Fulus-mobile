import 'package:fulus_mobile/core/errors/failure.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/secure_storage/secure_storage.dart';
import 'package:fulus_mobile/data/remote/api_client.dart';
import 'package:fulus_mobile/data/remote/endpoints/auth_api.dart';
import 'package:fulus_mobile/data/repositories/auth_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/auth_user.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthApi extends Mock implements AuthApi {}

class MockApiClient extends Mock implements ApiClient {}

class MockSecureStorage extends Mock implements SecureStorage {}

void main() {
  late MockAuthApi authApi;
  late MockApiClient apiClient;
  late MockSecureStorage secureStorage;
  late AppDatabase db;
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
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = AuthRepositoryImpl(
      authApi: authApi,
      apiClient: apiClient,
      secureStorage: secureStorage,
      db: db,
    );

    // Stub every mock call this repository might make with a harmless
    // default so tests only need to override what they actually care
    // about.
    when(() => apiClient.setAccessToken(any())).thenReturn(null);
    when(() => secureStorage.setRefreshToken(any())).thenAnswer((_) async {});
    when(() => secureStorage.deleteRefreshToken()).thenAnswer((_) async {});
  });

  tearDown(() async {
    await db.close();
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

    test('persists the session locally so it survives a later offline restart',
        () async {
      when(() => authApi.login(username: 'owner', password: 'secret1'))
          .thenAnswer((_) async => tokenResponse);

      await repository.login(username: 'owner', password: 'secret1');

      final rows = await db.select(db.sessions).get();
      expect(rows, hasLength(1));
      expect(rows.single.userId, 'user-1');
      expect(rows.single.username, 'owner');
      expect(rows.single.backendRole, 'admin');
      expect(rows.single.lastSyncedAt, isNotNull);
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
      expect(await db.select(db.sessions).get(), isEmpty);
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

    test('restores the session on a successful refresh, and refreshes the cached copy',
        () async {
      when(() => secureStorage.getRefreshToken())
          .thenAnswer((_) async => 'stored-refresh');
      when(() => authApi.refresh(refreshToken: 'stored-refresh'))
          .thenAnswer((_) async => tokenResponse);

      final result = await repository.restoreSession();

      expect(result?.id, 'user-1');
      expect(repository.currentUser?.id, 'user-1');
      verify(() => apiClient.setAccessToken('access-1')).called(1);
      final rows = await db.select(db.sessions).get();
      expect(rows, hasLength(1));
      expect(rows.single.userId, 'user-1');
    });

    test(
        'clears the stored refresh token AND the cached session when the '
        'server confirms the token is genuinely invalid', () async {
      // Seed a cached session first, as if a previous successful login
      // had happened on this device.
      when(() => authApi.login(username: 'owner', password: 'secret1'))
          .thenAnswer((_) async => tokenResponse);
      await repository.login(username: 'owner', password: 'secret1');

      when(() => secureStorage.getRefreshToken())
          .thenAnswer((_) async => 'stale-refresh');
      when(() => authApi.refresh(refreshToken: 'stale-refresh'))
          .thenThrow(const AuthFailure.sessionExpired());

      final result = await repository.restoreSession();

      expect(result, isNull);
      verify(() => secureStorage.deleteRefreshToken()).called(1);
      // The real point of this test: a deactivated/expired account must
      // not still appear "logged in" from local cache after this.
      expect(await db.select(db.sessions).get(), isEmpty);
    });

    test(
        'does NOT clear the stored refresh token on a network failure, and '
        'returns null when there is no cached session to fall back on',
        () async {
      when(() => secureStorage.getRefreshToken())
          .thenAnswer((_) async => 'still-good-refresh');
      when(() => authApi.refresh(refreshToken: 'still-good-refresh'))
          .thenThrow(const NetworkFailure.offline());

      final result = await repository.restoreSession();

      expect(result, isNull);
      verifyNever(() => secureStorage.deleteRefreshToken());
    });

    test(
        'falls back to the locally-cached session on a network failure when '
        'a previous login/refresh already confirmed one — the actual fix: '
        'this used to just return null here regardless, even with a '
        'perfectly good cached identity sitting in Sessions the whole time',
        () async {
      // A previous, successful launch already confirmed and cached this
      // user's session.
      when(() => authApi.login(username: 'owner', password: 'secret1'))
          .thenAnswer((_) async => tokenResponse);
      await repository.login(username: 'owner', password: 'secret1');

      // This launch's silent-refresh attempt hits a network failure.
      when(() => secureStorage.getRefreshToken())
          .thenAnswer((_) async => 'still-good-refresh');
      when(() => authApi.refresh(refreshToken: 'still-good-refresh'))
          .thenThrow(const NetworkFailure.offline());

      final result = await repository.restoreSession();

      expect(result, isNotNull);
      expect(result!.id, 'user-1');
      expect(result.username, 'owner');
      expect(repository.currentUser?.id, 'user-1');
      // Still not deleted — the refresh token might still be perfectly
      // valid, this launch just couldn't confirm it right now.
      verifyNever(() => secureStorage.deleteRefreshToken());
    });

    test(
        'replaces a DIFFERENT cached user rather than leaving both rows '
        'behind — "one phone, one signed-in user at a time"', () async {
      when(() => authApi.login(username: 'previous_user', password: 'x'))
          .thenAnswer(
        (_) async => const TokenResponseDto(
          accessToken: 'access-old',
          refreshToken: 'refresh-old',
          tokenType: 'bearer',
          user: UserDto(
            id: 'user-old',
            username: 'previous_user',
            email: 'previous@example.com',
            fullName: 'Previous User',
            role: 'cashier',
            isActive: true,
          ),
        ),
      );
      await repository.login(username: 'previous_user', password: 'x');

      when(() => authApi.login(username: 'owner', password: 'secret1'))
          .thenAnswer((_) async => tokenResponse);
      await repository.login(username: 'owner', password: 'secret1');

      final rows = await db.select(db.sessions).get();
      expect(rows, hasLength(1));
      expect(rows.single.userId, 'user-1');
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
      expect(await db.select(db.sessions).get(), isEmpty);
    });
  });
}
