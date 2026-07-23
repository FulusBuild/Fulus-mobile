import 'package:bms_mobile/core/security/pin_hasher.dart';
import 'package:bms_mobile/data/remote/endpoints/auth_api.dart';
import 'package:bms_mobile/data/repositories/approval_pin_repository_impl.dart';
import 'package:bms_mobile/data/local/secure_storage/secure_storage.dart';
import 'package:bms_mobile/domain/entities/approval_hash.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthApi extends Mock implements AuthApi {}

class MockSecureStorage extends Mock implements SecureStorage {}

/// Deterministic, pure-Dart fake — never used for anything resembling
/// real security. Lets these tests verify the repository's own
/// matching/replacement LOGIC without depending on dargon2_flutter's
/// native library loading correctly inside `flutter test`'s plain Dart
/// VM, which is a real, separate, unverified-from-this-environment risk
/// (see Argon2PinHasher's own doc comment in pin_hasher.dart).
class _FakePinHasher implements PinHasher {
  @override
  Future<PinHash> hash(String pin) async {
    return PinHash(hash: 'fake-hash:$pin', salt: 'fake-salt:$pin');
  }

  @override
  Future<bool> verify(
    String pin, {
    required String expectedHash,
    required String salt,
  }) async {
    return expectedHash == 'fake-hash:$pin' && salt == 'fake-salt:$pin';
  }
}

void main() {
  late MockAuthApi authApi;
  late MockSecureStorage secureStorage;
  late ApprovalPinRepositoryImpl repository;

  setUpAll(() {
    registerFallbackValue(<ApprovalPinVerifier>[]);
  });

  setUp(() {
    authApi = MockAuthApi();
    secureStorage = MockSecureStorage();
    repository = ApprovalPinRepositoryImpl(
      authApi: authApi,
      secureStorage: secureStorage,
      pinHasher: _FakePinHasher(),
    );

    when(() => authApi.setApprovalPin(
          pinHash: any(named: 'pinHash'),
          pinSalt: any(named: 'pinSalt'),
        )).thenAnswer((_) async {});
    when(() => secureStorage.setApprovalPinVerifiers(any()))
        .thenAnswer((_) async {});
  });

  group('setOwnApprovalPin', () {
    test('pushes the hash to the backend and stores it locally', () async {
      when(() => secureStorage.getApprovalPinVerifiers())
          .thenAnswer((_) async => []);

      await repository.setOwnApprovalPin(userId: 'user-1', pin: '1234');

      verify(() => authApi.setApprovalPin(
            pinHash: 'fake-hash:1234',
            pinSalt: 'fake-salt:1234',
          )).called(1);

      final captured = verify(
        () => secureStorage.setApprovalPinVerifiers(captureAny()),
      ).captured;
      final stored = captured.single as List<ApprovalPinVerifier>;
      expect(stored, hasLength(1));
      expect(stored.single.userId, 'user-1');
      expect(stored.single.hash, 'fake-hash:1234');
    });

    test('replaces an existing entry for the same user rather than duplicating',
        () async {
      when(() => secureStorage.getApprovalPinVerifiers()).thenAnswer(
        (_) async => [
          const ApprovalPinVerifier(userId: 'user-1', hash: 'old-hash', salt: 'old-salt'),
          const ApprovalPinVerifier(userId: 'user-2', hash: 'other-hash', salt: 'other-salt'),
        ],
      );

      await repository.setOwnApprovalPin(userId: 'user-1', pin: '5678');

      final captured = verify(
        () => secureStorage.setApprovalPinVerifiers(captureAny()),
      ).captured;
      final stored = captured.single as List<ApprovalPinVerifier>;
      expect(stored, hasLength(2)); // user-1 replaced, user-2 untouched
      final user1Entry = stored.firstWhere((v) => v.userId == 'user-1');
      expect(user1Entry.hash, 'fake-hash:5678');
      final user2Entry = stored.firstWhere((v) => v.userId == 'user-2');
      expect(user2Entry.hash, 'other-hash');
    });
  });

  group('syncApprovalHashes', () {
    test('replaces the local set with whatever the backend returns', () async {
      when(() => authApi.getApprovalHashes()).thenAnswer(
        (_) async => [
          const ApprovalHashEntryDto(
            userId: 'user-1', pinHash: 'h1', pinSalt: 's1',
          ),
          const ApprovalHashEntryDto(
            userId: 'user-2', pinHash: 'h2', pinSalt: 's2',
          ),
        ],
      );

      await repository.syncApprovalHashes();

      final captured = verify(
        () => secureStorage.setApprovalPinVerifiers(captureAny()),
      ).captured;
      final stored = captured.single as List<ApprovalPinVerifier>;
      expect(stored, hasLength(2));
      expect(stored.map((v) => v.userId), containsAll(['user-1', 'user-2']));
    });
  });

  group('verifyApprovalPin', () {
    test('returns the matching user id when the pin matches one verifier',
        () async {
      when(() => secureStorage.getApprovalPinVerifiers()).thenAnswer(
        (_) async => [
          const ApprovalPinVerifier(
            userId: 'user-1', hash: 'fake-hash:1111', salt: 'fake-salt:1111',
          ),
          const ApprovalPinVerifier(
            userId: 'user-2', hash: 'fake-hash:2222', salt: 'fake-salt:2222',
          ),
        ],
      );

      final result = await repository.verifyApprovalPin('2222');

      expect(result, 'user-2');
    });

    test('returns null when no stored verifier matches', () async {
      when(() => secureStorage.getApprovalPinVerifiers()).thenAnswer(
        (_) async => [
          const ApprovalPinVerifier(
            userId: 'user-1', hash: 'fake-hash:1111', salt: 'fake-salt:1111',
          ),
        ],
      );

      final result = await repository.verifyApprovalPin('9999');

      expect(result, isNull);
    });

    test('returns null immediately when there are no synced verifiers at all',
        () async {
      when(() => secureStorage.getApprovalPinVerifiers())
          .thenAnswer((_) async => []);

      final result = await repository.verifyApprovalPin('1234');

      expect(result, isNull);
    });
  });
}
