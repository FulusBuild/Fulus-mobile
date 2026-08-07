import '../errors/failure.dart';

/// Ported directly from backend/app/services/auth_service.py's
/// _validate_password_strength — verified against the actual function
/// body, not reconstructed from memory. Deliberately kept permissive
/// (length + at least one digit + one letter) rather than prescriptive —
/// per the original docstring, overly-complex rules lead to password
/// reuse, not stronger passwords. This rule is unrelated to networking
/// or the backend/mobile split, so the Architecture Redesign gives no
/// reason to change it — only to move where it's enforced.
class PasswordPolicy {
  const PasswordPolicy._();

  /// Mirrors settings.PASSWORD_MIN_LENGTH's value (backend/app/core/
  /// config.py) — verified directly, not assumed. If that default is
  /// ever changed on the backend side (there's no backend enforcing it
  /// anymore for mobile, but it's still the number this was copied
  /// from), update this constant to match by hand; nothing keeps the
  /// two in sync automatically now that they're two separate codebases.
  static const minLength = 8;

  /// Throws a [ValidationFailure] (mirroring the backend's
  /// ValidationError for this exact check) if [password] doesn't meet
  /// the policy. Returns normally if it does.
  static void validate(String password) {
    if (password.length < minLength) {
      throw ValidationFailure(
        fieldErrors: {
          'password': 'Password must be at least $minLength characters long.',
        },
      );
    }

    // Python's str.isalpha()/str.isdigit() are both Unicode-aware, not
    // ASCII-only — verified directly in the source rather than assumed,
    // since that's an easy thing to get subtly wrong porting between
    // languages. \p{L} (Unicode category "Letter") and \p{Nd} ("Decimal
    // Number") are the closest faithful Dart equivalents, not `[a-zA-Z]`
    // and `[0-9]`, so a password using non-Latin letters or non-ASCII
    // decimal digits is accepted exactly as it would be by the original
    // Python check.
    final hasLetter = RegExp(r'\p{L}', unicode: true).hasMatch(password);
    final hasDigit = RegExp(r'\p{Nd}', unicode: true).hasMatch(password);
    if (!hasLetter || !hasDigit) {
      throw const ValidationFailure(
        fieldErrors: {
          'password': 'Password must contain at least one letter and one number.',
        },
      );
    }
  }
}
