import 'dart:async';

import '../../core/security/pin_hasher.dart';
import '../../domain/entities/approval_hash.dart';
import '../../domain/repositories/approval_pin_repository.dart';
import '../../domain/repositories/audit_repository.dart';
import '../local/secure_storage/secure_storage.dart';
import '../remote/endpoints/auth_api.dart';

class ApprovalPinRepositoryImpl implements ApprovalPinRepository {
  ApprovalPinRepositoryImpl({
    required AuthApi authApi,
    required SecureStorage secureStorage,
    required PinHasher pinHasher,
    required AuditRepository auditRepository,
  })  : _authApi = authApi,
        _secureStorage = secureStorage,
        _pinHasher = pinHasher,
        _auditRepository = auditRepository;

  final AuthApi _authApi;
  final SecureStorage _secureStorage;
  final PinHasher _pinHasher;
  final AuditRepository _auditRepository;

  @override
  Future<void> setOwnApprovalPin({
    required String userId,
    required String pin,
  }) async {
    final pinHash = await _pinHasher.hash(pin);

    // CORRECTED (Architecture Redesign audit pass): this used to await
    // _authApi.setApprovalPin BEFORE the local write below, which meant
    // setting your own approval PIN — entirely this device's own local
    // business, per Volume 9 — silently required network connectivity
    // to complete at all, a direct violation of "must work 100%
    // offline. Everything." The local write is now unconditional and
    // first; pushing the hash to the backend (so OTHER employees'
    // devices can eventually verify it too) is best-effort and
    // non-blocking, matching the exact pattern bootstrap.dart already
    // uses for every other pull-sync call (locationRepository,
    // businessSettingsRepository, productRepository).
    final existing = await _secureStorage.getApprovalPinVerifiers();
    final updated = [
      ...existing.where((v) => v.userId != userId),
      ApprovalPinVerifier(userId: userId, hash: pinHash.hash, salt: pinHash.salt),
    ];
    await _secureStorage.setApprovalPinVerifiers(updated);

    // Mirrors the backend's own SET_APPROVAL_PIN action exactly
    // (verified directly against routers/auth.py) — recorded once the
    // local write actually succeeds, regardless of whether the
    // best-effort push below ever reaches a server.
    await _auditRepository.log(
      action: 'SET_APPROVAL_PIN',
      module: 'AUTH',
      userId: userId,
    );

    unawaited(
      _authApi
          .setApprovalPin(pinHash: pinHash.hash, pinSalt: pinHash.salt)
          .catchError((_) {}),
    );
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
