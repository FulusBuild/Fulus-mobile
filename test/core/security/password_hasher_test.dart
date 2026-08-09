import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:fulus_mobile/core/security/password_hasher.dart';
import 'package:flutter_test/flutter_test.dart';

/// Argon2PasswordHasher was, until this fix, the one piece of this
/// codebase's security-critical logic that genuinely could not be
/// exercised from `flutter test`'s plain Dart VM — dargon2_flutter's
/// native library only loads on a real device (see the test/repository
/// fakes' own comments for how that gap was worked around, and
/// password_hasher.dart's doc comment for the full story). Now that
/// hashing is pure Dart, this file runs the real class for real.
///
/// One honest limit: this suite proves Argon2PasswordHasher is
/// internally consistent (hash/verify agree, salts are actually random,
/// the wired-up parameters match what's documented) and wires
/// cryptography's Argon2id correctly. It does not check output against
/// an official RFC 9106 known-answer test vector — the published
/// vectors use a non-empty "secret" and "associated data" input that
/// cryptography's own Argon2id API has no parameter for, so there's no
/// vector this class's actual call shape could reproduce. If bit-for-
/// bit interop with another Argon2id implementation (e.g. verifying a
/// hash produced by the old dargon2_flutter against one from this class)
/// ever matters, that's worth checking on a real device separately.
void main() {
  const hasher = Argon2PasswordHasher();
  const password = 'correct horse battery staple';

  group('hash', () {
    late PasswordHash hashed;

    // One real Argon2id computation (memory-hard by design, so
    // deliberately not cheap), shared by every test in this group
    // rather than recomputed per test.
    setUpAll(() async {
      hashed = await hasher.hash(password);
    });

    test('produces a non-empty, base64-decodable hash and salt', () {
      expect(hashed.hash, isNotEmpty);
      expect(hashed.salt, isNotEmpty);
      expect(() => base64Decode(hashed.hash), returnsNormally);
      expect(() => base64Decode(hashed.salt), returnsNormally);
    });

    test('hash is 32 bytes and salt is 16 bytes, matching the configured lengths', () {
      expect(base64Decode(hashed.hash), hasLength(32));
      expect(base64Decode(hashed.salt), hasLength(16));
    });

    test('two calls for the same password get different, independently random salts', () async {
      final second = await hasher.hash(password);
      expect(second.salt, isNot(equals(hashed.salt)));
      // A different salt must change the hash too, even for the exact
      // same password — otherwise salt wouldn't actually be feeding
      // into the computation.
      expect(second.hash, isNot(equals(hashed.hash)));
    });
  });

  group('verify', () {
    late PasswordHash hashed;

    setUpAll(() async {
      hashed = await hasher.hash(password);
    });

    test('succeeds for the correct password against its own hash and salt', () async {
      final ok = await hasher.verify(password, expectedHash: hashed.hash, salt: hashed.salt);
      expect(ok, isTrue);
    });

    test('fails for an incorrect password', () async {
      final ok = await hasher.verify(
        'wrong password entirely',
        expectedHash: hashed.hash,
        salt: hashed.salt,
      );
      expect(ok, isFalse);
    });

    test('fails when checked against a salt other than the one the hash was produced with', () async {
      final unrelatedSalt = base64Encode(List<int>.filled(16, 7));
      final ok = await hasher.verify(password, expectedHash: hashed.hash, salt: unrelatedSalt);
      expect(ok, isFalse);
    });
  });

  test(
    'wired-up parameters match the documented OWASP baseline '
    '(m=19456 KiB, t=2, p=1, Argon2id, 32-byte output)',
    () async {
      // Deliberately does not import anything from password_hasher.dart
      // beyond the class under test — this file keeps its own copy of
      // the expected parameters and builds an independent Argon2id
      // against the same public API Argon2PasswordHasher itself wraps.
      // If a future edit to that class ever drifted from the baseline
      // documented in its own comments (say, iterations and
      // parallelism accidentally swapped), this is the test that would
      // catch it: hash()/verify() would still agree with *themselves*
      // in that scenario, which is why the groups above alone
      // wouldn't notice.
      final hashed = await hasher.hash(password);
      final reference = Argon2id(memory: 19456, iterations: 2, parallelism: 1, hashLength: 32);
      final key = await reference.deriveKeyFromPassword(
        password: password,
        nonce: base64Decode(hashed.salt),
      );
      final expectedHash = base64Encode(await key.extractBytes());
      expect(hashed.hash, expectedHash);
    },
  );
}
