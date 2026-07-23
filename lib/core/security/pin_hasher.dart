import 'dart:convert';

import 'package:dargon2_flutter/dargon2_flutter.dart';

/// One stored PIN verifier — the wire/storage shape shared between
/// SecureStorage and the backend's own pin_hash/pin_salt columns
/// (users table, migration 0011_approval_pin).
class PinHash {
  const PinHash({required this.hash, required this.salt});

  final String hash;
  final String salt;
}

/// Architecture Section 11: "Argon2id, via a well-audited platform
/// binding — not hand-rolled." Abstracted behind this interface
/// specifically so the PIN-matching/comparison LOGIC in
/// ApprovalPinRepositoryImpl (which admin's PIN matched, if any) can be
/// unit-tested with a fake implementation — dargon2_flutter's native
/// library loading correctly inside `flutter test`'s plain Dart VM
/// (rather than a real device/emulator) is a genuinely separate,
/// unverified-from-this-sandboxed-environment risk from whether that
/// surrounding logic is correct, and this split lets the latter be
/// tested for real regardless of the former.
abstract class PinHasher {
  /// Hashes [pin] with a freshly generated random salt.
  Future<PinHash> hash(String pin);

  /// Re-hashes [pin] with the given, already-stored [salt] and compares
  /// the result against [expectedHash]. Returns true on an exact match.
  Future<bool> verify(String pin, {required String expectedHash, required String salt});
}

/// The real implementation, verified directly against dargon2_flutter's
/// published API (pub.dev/documentation/dargon2_interface) rather than
/// assumed — this environment has no way to actually execute this
/// class (no Flutter SDK, no device), so that verification is the most
/// I can do here; see this project's own notes on where genuine
/// execution still needs to happen.
class Argon2PinHasher implements PinHasher {
  const Argon2PinHasher();

  // OWASP Password Storage Cheat Sheet's first recommended Argon2id
  // baseline (m=19456 KiB / ~19 MiB, t=2, p=1) — deliberately NOT
  // dargon2_flutter's own README example default (memory: 256): a real
  // GitHub issue filed against this exact package
  // (GlitterWare/Passy#113) shows that value throwing
  // ARGON2_MEMORY_TOO_LITTLE, confirming the parameter's unit is KiB
  // (matching the reference Argon2 C library's own convention) and that
  // 256 is a README toy value, not a production-appropriate one.
  //
  // Chosen with this PIN's own specific threat model in mind, not
  // generic password-hashing guidance: a 4-digit PIN has only 10,000
  // possible values, so even Argon2id's deliberate slowness can't make
  // brute-forcing every value impossible if the hash+salt are ever
  // extracted directly from the device — only slow enough to matter.
  // At these parameters, exhausting all 10,000 combinations takes
  // meaningfully long without making any single legitimate check
  // (performed on every approval, not just once at login) noticeably
  // slow.
  static const _saltLengthBytes = 16;
  static const _memoryKib = 19456;
  static const _iterations = 2;
  static const _parallelism = 1;
  static const _hashLength = 32;

  @override
  Future<PinHash> hash(String pin) async {
    final salt = Salt.newSalt(length: _saltLengthBytes);
    final hashValue = await _hashWithSalt(pin, salt);
    return PinHash(hash: hashValue, salt: base64Encode(salt.bytes));
  }

  @override
  Future<bool> verify(
    String pin, {
    required String expectedHash,
    required String salt,
  }) async {
    // Deliberately NOT argon2.verifyHashString/verifyHashBytes — those
    // expect Argon2's self-describing ENCODED format (salt and params
    // embedded in the string itself), which is a different shape from
    // this class's own storage design (explicit, separately-stored
    // hash and salt, matching the backend's two separate columns). Re-
    // hashing with the same explicit salt and comparing the raw result
    // directly is the correct operation for that storage shape.
    final saltObj = Salt(base64Decode(salt));
    final actualHash = await _hashWithSalt(pin, saltObj);
    // A plain == comparison, not a constant-time one — deliberately:
    // this runs entirely on-device, comparing against a value already
    // resident in this same process's memory, for an offline check
    // during normal app use. It is not a network-facing comparison
    // where a remote attacker could measure timing differences, which
    // is the actual scenario constant-time comparison defends against.
    return actualHash == expectedHash;
  }

  Future<String> _hashWithSalt(String pin, Salt salt) async {
    final result = await argon2.hashPasswordString(
      pin,
      salt: salt,
      iterations: _iterations,
      memory: _memoryKib,
      parallelism: _parallelism,
      length: _hashLength,
      // The default type is Argon2i (dargon2_flutter's own documented
      // default) — Argon2id must be passed explicitly, or this would
      // silently hash with the wrong variant.
      type: Argon2Type.id,
    );
    return result.base64String;
  }
}
