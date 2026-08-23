import 'package:dio/dio.dart';

import '../../../errors/failure.dart';
import '../../models/diagnostic_event.dart';
import '../diagnostic_rule.dart';
import '../diagnostic_signal.dart';

/// Auth-related rules split deliberately into two different real
/// causes, matching this app's own architecture rather than the
/// brief's single illustrative "HTTP 401 + expired session" example
/// verbatim: since the Architecture Redesign, sign-in is entirely
/// local (core/errors/failure.dart's own header comment), so a *local*
/// session becoming invalid and a *sync* HTTP 401 are genuinely
/// different failures with different likely explanations, not the same
/// thing reached two ways.
///
/// Matched on [AuthFailure]'s own public `.message` — this app already
/// throws/catches [Failure] subtypes as real exceptions (see
/// sync_engine.dart's own `on AuthFailure catch (e)`), and each
/// variant's message is a fixed, deliberately-worded string (verified
/// directly against failure.dart) — stable enough to match on safely.
/// The individual variant classes themselves are private to that file
/// and can't be named here, which is exactly why message-matching,
/// not a type switch, is the right tool.
class LocalSessionInvalidRule extends DiagnosticRule {
  const LocalSessionInvalidRule();

  @override
  String get name => 'auth.localSessionInvalid';

  @override
  bool matches(DiagnosticSignal signal) {
    final error = signal.error;
    return error is AuthFailure && error.message.contains('sign in again');
  }

  @override
  DiagnosticCause apply(DiagnosticSignal signal) => const DiagnosticCause(
        description: "The signed-in user's local session stopped being valid — "
            'most often because they were deactivated or had their access changed '
            'from another device while still signed in on this one.',
        confidence: DiagnosticConfidence.high,
      );
}

class AccountDeactivatedRule extends DiagnosticRule {
  const AccountDeactivatedRule();

  @override
  String get name => 'auth.accountDeactivated';

  @override
  bool matches(DiagnosticSignal signal) {
    final error = signal.error;
    return error is AuthFailure && error.message.contains('deactivated');
  }

  @override
  DiagnosticCause apply(DiagnosticSignal signal) => const DiagnosticCause(
        description: 'This account has been deactivated (by an owner, on this or '
            'another device) and can no longer sign in.',
        confidence: DiagnosticConfidence.high,
      );
}

class AccountLockedRule extends DiagnosticRule {
  const AccountLockedRule();

  @override
  String get name => 'auth.accountLocked';

  @override
  bool matches(DiagnosticSignal signal) {
    final error = signal.error;
    return error is AuthFailure && error.message.contains('Too many attempts');
  }

  @override
  DiagnosticCause apply(DiagnosticSignal signal) => const DiagnosticCause(
        description: 'This account was temporarily locked after too many failed '
            'sign-in attempts in a row.',
        confidence: DiagnosticConfidence.high,
      );
}

/// The brief's own literal "HTTP 401 + expired session" example — real
/// in this app only at the Sync boundary (ApiClient/AuthApi), where a
/// 401 surfacing this far means a silent token refresh already failed
/// (see api_client.dart's own comment on `mapError`'s 401 case).
class SyncAuthRejectedRule extends DiagnosticRule {
  const SyncAuthRejectedRule();

  @override
  String get name => 'auth.syncRejected';

  @override
  bool matches(DiagnosticSignal signal) {
    final error = signal.error;
    return error is DioException && error.response?.statusCode == 401;
  }

  @override
  DiagnosticCause apply(DiagnosticSignal signal) => const DiagnosticCause(
        description: "The server rejected this device's sync credentials.",
        confidence: DiagnosticConfidence.high,
      );

  @override
  List<EvidenceItem> evidenceFor(DiagnosticSignal signal) =>
      const [EvidenceItem('HTTP status', '401')];
}

class ForbiddenRule extends DiagnosticRule {
  const ForbiddenRule();

  @override
  String get name => 'auth.forbidden';

  @override
  bool matches(DiagnosticSignal signal) {
    final error = signal.error;
    return error is AuthFailure && error.message.contains("don't have permission");
  }

  @override
  DiagnosticCause apply(DiagnosticSignal signal) => const DiagnosticCause(
        description: "The signed-in user's role does not permit this action — "
            'most often a stale locally-cached permission after a role change '
            'synced down from another device.',
        confidence: DiagnosticConfidence.medium,
      );
}

const List<DiagnosticRule> authRules = [
  LocalSessionInvalidRule(),
  AccountDeactivatedRule(),
  AccountLockedRule(),
  ForbiddenRule(),
  SyncAuthRejectedRule(),
];
