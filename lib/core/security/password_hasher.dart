import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

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

/// Was implemented against dargon2_flutter (an FFI binding to the
/// Argon2 reference C library) until the bugreport pasted into this
/// session confirmed it unusable on Android: dargon2_flutter_mobile's
/// own native-library loader throws "dlopen failed: library
/// 'libargon2-arm.so' not found" during Flutter's plugin registration,
/// every time, on this device. That's not a packaging mistake in this
/// project's own android/app/build.gradle — there's no abiFilters or
/// other ABI restriction there that would explain a missing native
/// lib — it's a real, still-open, upstream bug in the plugin itself:
/// github.com/tmthecoder/dargon2/issues/26, filed September 2024,
/// zero maintainer response since. The same repository also has issue
/// #27 (open since September 2025) for a second, unrelated Dart-3.0+
/// incompatibility, which this project's own Dart SDK constraint
/// (>=3.3.0) would also have hit. Both open for a year or more with no
/// fix: this isn't a plugin having a bad day, it's unmaintained on any
/// currently-supported toolchain.
///
/// cryptography's Argon2id (pub.dev/documentation/cryptography) is
/// pure Dart, so there's no native binary to (mis)package per-ABI in
/// the first place — the entire bug class above doesn't apply to it.
/// It's still genuinely Argon2id — RFC 9106, the same variant Section
/// 11 asks for — not a weaker algorithm substituted to route around
/// the real problem. The one honest caveat on "well-audited": the
/// previous implementation delegated to the actual Argon2 reference C
/// implementation (the Password Hashing Competition winner's own
/// code), which carries a specific audit lineage a pure-Dart port
/// necessarily doesn't inherit just by implementing the same published
/// algorithm correctly. cryptography is a widely-used, actively
/// maintained package (dint.dev, a pub.dev verified publisher) with
/// its own test-vector coverage, but that's a different, weaker claim
/// than "this exact binary has been through the same audit as the
/// reference implementation." Worth Section 11's own wording
/// reflecting that if this change sticks.
///
/// Unlike the class it replaces, this one has actually been run:
/// dargon2_flutter needed a real device to exercise at all (its native
/// lib only loads there, not in `flutter test`'s plain Dart VM — see
/// the fake hashers in test/repository/*_test.dart, added specifically
/// to route around that gap). cryptography's Argon2id has no such
/// requirement, so password_hasher_test.dart (added alongside this
/// change) runs this class for real under `dart test`/`flutter test`
/// — no native toolchain, no device, no emulator needed. That's the
/// verification this file's previous version could only gesture at
/// from this sandboxed environment; the specific case of `flutter run`
/// on Jj's actual device is still the genuine end-to-end check, but it
/// no longer needs to be the *only* check.
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
  //
  // cryptography's Argon2id takes `memory` as a plain KB integer (no
  // power-of-two rounding, unlike e.g. pointycastle's
  // `memoryPowerOf2`), so 19456 carries over from the OWASP figure
  // unchanged — no rounding compromise from the switch.
  static const _saltLengthBytes = 16;
  static const _memoryKib = 19456;
  static const _iterations = 2;
  static const _parallelism = 1;
  static const _hashLength = 32;

  // Stateless config, built once and reused — not `const` because
  // Argon2id's constructor isn't declared const, but `static final`
  // gets the same "computed once, shared" effect. Requesting the
  // `id` variant is implicit in the class name here, unlike
  // dargon2_flutter's API, which defaulted to Argon2i and needed
  // `type: Argon2Type.id` passed explicitly on every call — one fewer
  // way for this to silently hash with the wrong variant.
  static final _algorithm = Argon2id(
    memory: _memoryKib,
    iterations: _iterations,
    parallelism: _parallelism,
    hashLength: _hashLength,
  );

  @override
  Future<PasswordHash> hash(String password) async {
    final salt = _newSalt();
    final hashValue = await _hashWithSalt(password, salt);
    return PasswordHash(hash: hashValue, salt: base64Encode(salt));
  }

  @override
  Future<bool> verify(
    String password, {
    required String expectedHash,
    required String salt,
  }) async {
    final saltBytes = base64Decode(salt);
    final actualHash = await _hashWithSalt(password, saltBytes);
    // A plain == comparison, not constant-time — same reasoning as
    // Argon2PinHasher.verify: this runs entirely on-device against a
    // value already resident in this process's memory, not across a
    // network boundary where timing could be measured remotely.
    return actualHash == expectedHash;
  }

  Future<String> _hashWithSalt(String password, List<int> salt) async {
    // cryptography's naming: what dargon2_flutter/Argon2 spec calls
    // "salt" is passed here as `nonce` — same 16 random bytes, same
    // role, just this package's term for a KDF's per-call unique
    // input.
    final secretKey = await _algorithm.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final bytes = await secretKey.extractBytes();
    return base64Encode(bytes);
  }

  /// dart:math's `Random.secure()` — the CSPRNG the Dart SDK itself
  /// provides, backed by the OS's secure random source. Same source
  /// cryptography's own README says it uses as its own default
  /// throughout that package; no need for a second RNG dependency just
  /// for 16 bytes of salt.
  Uint8List _newSalt() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(_saltLengthBytes, (_) => random.nextInt(256)),
    );
  }
}
