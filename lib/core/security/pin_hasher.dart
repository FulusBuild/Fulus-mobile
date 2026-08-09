import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

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
/// unit-tested with a fake implementation — see Argon2PinHasher's own
/// doc comment for why that separation, originally there to route
/// around dargon2_flutter's native-library limitations in `flutter
/// test`, is no longer load-bearing the same way but is kept anyway
/// since it's still the right layering on its own merits.
abstract class PinHasher {
  /// Hashes [pin] with a freshly generated random salt.
  Future<PinHash> hash(String pin);

  /// Re-hashes [pin] with the given, already-stored [salt] and compares
  /// the result against [expectedHash]. Returns true on an exact match.
  Future<bool> verify(String pin, {required String expectedHash, required String salt});
}

/// Was implemented against dargon2_flutter until the bugreport pasted
/// into this session confirmed it unusable on Android — see
/// Argon2PasswordHasher's doc comment (core/security/password_hasher.dart)
/// for the full root-cause writeup; this class hit the exact same
/// failure for the exact same reason, since both are thin wrappers
/// around the same broken plugin. Short version: dargon2_flutter_mobile's
/// native-library loader throws "dlopen failed: library
/// 'libargon2-arm.so' not found" on this device, which is a real,
/// still-open, ~2-year-unaddressed upstream bug
/// (github.com/tmthecoder/dargon2/issues/26), not a misconfiguration in
/// this project's own Android build.
///
/// cryptography's Argon2id is pure Dart — no native library, so no
/// per-ABI packaging for it to get wrong — and is still genuinely
/// Argon2id, not a weaker stand-in. pin_hasher_test.dart (added
/// alongside this change) now runs this class for real under `dart
/// test`/`flutter test`, which dargon2_flutter's native dependency
/// never allowed from a plain Dart VM.
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
  // cryptography's Argon2id takes `memory` as a plain KB integer too
  // (no power-of-two rounding), so 19456 carries over unchanged.
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

  // Stateless config, built once and reused. The `id` variant is
  // implicit in the class name here, unlike dargon2_flutter's API,
  // which defaulted to Argon2i and needed `type: Argon2Type.id` passed
  // explicitly on every call.
  static final _algorithm = Argon2id(
    memory: _memoryKib,
    iterations: _iterations,
    parallelism: _parallelism,
    hashLength: _hashLength,
  );

  @override
  Future<PinHash> hash(String pin) async {
    final salt = _newSalt();
    final hashValue = await _hashWithSalt(pin, salt);
    return PinHash(hash: hashValue, salt: base64Encode(salt));
  }

  @override
  Future<bool> verify(
    String pin, {
    required String expectedHash,
    required String salt,
  }) async {
    // Deliberately not any self-describing encoded hash format — that
    // would be a different shape from this class's own storage design
    // (explicit, separately-stored hash and salt, matching the
    // backend's two separate columns). Re-hashing with the same
    // explicit salt and comparing the raw result directly is the
    // correct operation for that storage shape.
    final saltBytes = base64Decode(salt);
    final actualHash = await _hashWithSalt(pin, saltBytes);
    // A plain == comparison, not a constant-time one — deliberately:
    // this runs entirely on-device, comparing against a value already
    // resident in this same process's memory, for an offline check
    // during normal app use. It is not a network-facing comparison
    // where a remote attacker could measure timing differences, which
    // is the actual scenario constant-time comparison defends against.
    return actualHash == expectedHash;
  }

  Future<String> _hashWithSalt(String pin, List<int> salt) async {
    // cryptography's naming: what the Argon2 spec calls "salt" is
    // passed here as `nonce` — same 16 random bytes, same role.
    final secretKey = await _algorithm.deriveKeyFromPassword(
      password: pin,
      nonce: salt,
    );
    final bytes = await secretKey.extractBytes();
    return base64Encode(bytes);
  }

  /// dart:math's `Random.secure()` — the CSPRNG the Dart SDK itself
  /// provides, backed by the OS's secure random source.
  Uint8List _newSalt() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(_saltLengthBytes, (_) => random.nextInt(256)),
    );
  }
}
