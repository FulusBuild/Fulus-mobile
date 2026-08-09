import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:fulus_mobile/core/security/pin_hasher.dart';
import 'package:flutter_test/flutter_test.dart';

/// See password_hasher_test.dart's own doc comment — same story here:
/// Argon2PinHasher used to be untestable from `flutter test`'s plain
/// Dart VM (dargon2_flutter's native lib only loaded on a real device),
/// and now it isn't. Same honest limit applies too: this checks
/// internal consistency and correct parameter wiring, not conformance
/// to an official RFC 9106 known-answer vector — see that file for why.
///
/// PinHasher doesn't validate that [pin] looks like a 4-digit PIN (that
/// belongs to whatever calls it, e.g. ApprovalPinRepositoryImpl or a UI
/// field validator) — it hashes whatever string it's given. '1234' is
/// used below purely as a realistic example, not because the class
/// itself treats it specially.
void main() {
  const hasher = Argon2PinHasher();
  const pin = '1234';

  group('hash', () {
    late PinHash hashed;

    // One real Argon2id computation, shared by every test in this
    // group rather than recomputed per test.
    setUpAll(() async {
      hashed = await hasher.hash(pin);
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

    test('two calls for the same PIN get different, independently random salts', () async {
      final second = await hasher.hash(pin);
      expect(second.salt, isNot(equals(hashed.salt)));
      expect(second.hash, isNot(equals(hashed.hash)));
    });
  });

  group('verify', () {
    late PinHash hashed;

    setUpAll(() async {
      hashed = await hasher.hash(pin);
    });

    test('succeeds for the correct PIN against its own hash and salt', () async {
      final ok = await hasher.verify(pin, expectedHash: hashed.hash, salt: hashed.salt);
      expect(ok, isTrue);
    });

    test('fails for an incorrect PIN', () async {
      final ok = await hasher.verify('9999', expectedHash: hashed.hash, salt: hashed.salt);
      expect(ok, isFalse);
    });

    test('fails when checked against a salt other than the one the hash was produced with', () async {
      final unrelatedSalt = base64Encode(List<int>.filled(16, 7));
      final ok = await hasher.verify(pin, expectedHash: hashed.hash, salt: unrelatedSalt);
      expect(ok, isFalse);
    });
  });

  test(
    'wired-up parameters match the documented OWASP baseline '
    '(m=19456 KiB, t=2, p=1, Argon2id, 32-byte output)',
    () async {
      // Same reasoning as the matching test in password_hasher_test.dart:
      // an independently-built Argon2id, using this file's own copy of
      // the expected parameters rather than anything imported from
      // pin_hasher.dart, so a future drift in that class's actual
      // parameters would show up here even though hash()/verify() would
      // still agree with themselves either way.
      final hashed = await hasher.hash(pin);
      final reference = Argon2id(memory: 19456, iterations: 2, parallelism: 1, hashLength: 32);
      final key = await reference.deriveKeyFromPassword(
        password: pin,
        nonce: base64Decode(hashed.salt),
      );
      final expectedHash = base64Encode(await key.extractBytes());
      expect(hashed.hash, expectedHash);
    },
  );
}
