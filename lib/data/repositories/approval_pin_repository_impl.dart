import '../../core/security/pin_hasher.dart';
import '../../domain/entities/approval_hash.dart';
import '../../domain/repositories/approval_pin_repository.dart';
import '../local/secure_storage/secure_storage.dart';
import '../remote/endpoints/auth_api.dart';

class ApprovalPinRepositoryImpl implements ApprovalPinRepository {
  ApprovalPinRepositoryImpl({
    required AuthApi authApi,
    required SecureStorage secureStorage,
    required PinHasher pinHasher,
  })  : _authApi = authApi,
        _secureStorage = secureStorage,
        _pinHasher = pinHasher;

  final AuthApi _authApi;
  final SecureStorage _secureStorage;
  final PinHasher _pinHasher;

  @override
  Future<void> setOwnApprovalPin({
    required String userId,
    required String pin,
  }) async {
    final pinHash = await _pinHasher.hash(pin);
    await _authApi.setApprovalPin(pinHash: pinHash.hash, pinSalt: pinHash.salt);

    // Also stored locally immediately, rather than waiting for a
    // separate syncApprovalHashes() call — the owner's OWN device
    // should already be able to verify their own just-set PIN offline,
    // not only every OTHER employee's device once THEY separately
    // sync. Replaces any existing entry for this same userId rather
    // than appending, since setting a new PIN must supersede the old
    // one, never leave both matchable.
    final existing = await _secureStorage.getApprovalPinVerifiers();
    final updated = [
      ...existing.where((v) => v.userId != userId),
      ApprovalPinVerifier(userId: userId, hash: pinHash.hash, salt: pinHash.salt),
    ];
    await _secureStorage.setApprovalPinVerifiers(updated);
  }

  @override
  Future<void> syncApprovalHashes() async {
    final entries = await _authApi.getApprovalHashes();
    await _secureStorage.setApprovalPinVerifiers(
      entries.map((e) => e.toDomain()).toList(),
    );
  }

  @override
  Future<String?> verifyApprovalPin(String pin) async {
    final verifiers = await _secureStorage.getApprovalPinVerifiers();
    // Sequential, not parallel: each verifier has its own salt, so each
    // needs its own full Argon2id computation — deliberately not run
    // concurrently, since that would have multiple CPU/memory-intensive
    // hashes contend for the same limited mobile hardware rather than
    // genuinely speed things up. This does mean the worst case (no
    // match, checked against every admin) scales with how many owners
    // a business has — realistically a handful at most, so noticeable
    // but not a redesign-worthy cost.
    for (final verifier in verifiers) {
      final matches = await _pinHasher.verify(
        pin,
        expectedHash: verifier.hash,
        salt: verifier.salt,
      );
      if (matches) return verifier.userId;
    }
    return null;
  }
}
