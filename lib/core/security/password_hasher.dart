import 'dart:convert';

import 'package:dargon2_flutter/dargon2_flutter.dart';

/// One stored password verifier — the local Users table's own
/// hashedPassword/passwordSalt columns (see tables.dart), replacing what
/// used to be the backend's users.hashed_password column (bcrypt, via
/// passlib) now that login is checked locally instead of server-side.
class PasswordHash {
  const PasswordHash({required this.hash, required this.salt});

  final String hash;
  final String salt;
}

/// Architecture Section 11: "Argon2id, via a well-audited platform
/// binding — not hand-rolled." Same requirement PinHasher already
/// satisfies, and deliberately a separate interface from PinHasher
/// rather than one shared "SecretHasher" — a login password and an
/// approval PIN are different secrets with different call sites
/// (AuthRepositoryImpl vs ApprovalPinRepositoryImpl), and keeping them
/// as distinct types means a repository can't accidentally verify a
/// password against a stored PIN hash, or vice versa, and have it
/// silently type-check. The underlying implementation is structurally
/// identical to Argon2PinHasher's on purpose — see the parameter choice
/// note below — so the duplication this costs is small and deliberate,
/// not an oversight.
abstract class PasswordHasher {
  /// Hashes [password] with a freshly generated random salt.
  Future<PasswordHash> hash(String password);

  /// Re-hashes [password] with the given, already-stored [salt] and
  /// compares the result against [expectedHash]. Returns true on an
  /// exact match.
  Future<bool> verify(
    String password, {
    required String expectedHash,
    required String salt,
  });
}

/// Verified directly against dargon2_flutter's published API
/// (pub.dev/documentation/dargon2_interface), same as Argon2PinHasher —
/// this environment has no Flutter SDK or device to actually execute
/// this class against, so that verification is the most that could be
/// done here; genuine execution still needs to happen on a real
/// toolchain before this ships.
class Argon2PasswordHasher implements PasswordHasher {
  const Argon2PasswordHasher();

  // Identical parameters to Argon2PinHasher, and for a stronger reason
  // here than there: this is the OWASP Password Storage Cheat Sheet's
  // first recommended Argon2id baseline (m=19456 KiB / ~19 MiB, t=2,
  // p=1) — PinHasher already uses this same baseline even though a
  // 4-digit PIN's much smaller keyspace would arguably tolerate lighter
  // parameters, specifically so both secrets get the same, unambiguous,
  // "this is simply the correct baseline" treatment rather than two
  // different tuned values that would need two different
  // justifications. A real login password's keyspace is why this
  // baseline exists in the first place, so no adjustment is needed here
  // at all — this is parameters used exactly as OWASP intends them.
  static const _saltLengthBytes = 16;
  static const _memoryKib = 19456;
  static const _iterations = 2;
  static const _parallelism = 1;
  static const _hashLength = 32;

  @override
  Future<PasswordHash> hash(String password) async {
    final salt = Salt.newSalt(length: _saltLengthBytes);
    final hashValue = await _hashWithSalt(password, salt);
    return PasswordHash(hash: hashValue, salt: base64Encode(salt.bytes));
  }

  @override
  Future<bool> verify(
    String password, {
    required String expectedHash,
    required String salt,
  }) async {
    // Same explicit-hash-and-salt-stored-separately shape as
    // Argon2PinHasher, and the same reasoning applies: re-hash with the
    // stored salt and compare directly, rather than using
    // argon2.verifyHashString's self-describing encoded format.
    final saltObj = Salt(base64Decode(salt));
    final actualHash = await _hashWithSalt(password, saltObj);
    // A plain == comparison, not constant-time — same reasoning as
    // Argon2PinHasher.verify: this runs entirely on-device against a
    // value already resident in this process's memory, not across a
    // network boundary where timing could be measured remotely.
    return actualHash == expectedHash;
  }

  Future<String> _hashWithSalt(String password, Salt salt) async {
    final result = await argon2.hashPasswordString(
      password,
      salt: salt,
      iterations: _iterations,
      memory: _memoryKib,
      parallelism: _parallelism,
      length: _hashLength,
      // Must be passed explicitly — dargon2_flutter's own documented
      // default is Argon2i, not Argon2id.
      type: Argon2Type.id,
    );
    return result.base64String;
  }
}
