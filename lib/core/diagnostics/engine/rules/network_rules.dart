import 'package:dio/dio.dart';

import '../../models/diagnostic_event.dart';
import '../diagnostic_rule.dart';
import '../diagnostic_signal.dart';

/// Rules for the networked Sync layer — the only part of this app that
/// still makes HTTP calls at all (see core/errors/failure.dart's own
/// header comment on the Architecture Redesign that moved the core app
/// off any client/server boundary). Matched primarily on [DioException]
/// shape, since api_client.dart's own `mapError` already gives a
/// reliable, first-party signal for exactly this rather than needing to
/// guess from a generic exception's text.
class OfflineBeforeResponseRule extends DiagnosticRule {
  const OfflineBeforeResponseRule();

  @override
  String get name => 'network.offlineBeforeResponse';

  @override
  bool matches(DiagnosticSignal signal) {
    final error = signal.error;
    if (signal.isOffline == true) return true;
    if (error is DioException) {
      return error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout;
    }
    return false;
  }

  @override
  DiagnosticCause apply(DiagnosticSignal signal) => const DiagnosticCause(
        description: 'The device was offline (or lost connectivity mid-request) '
            'when this request was attempted.',
        confidence: DiagnosticConfidence.high,
      );

  @override
  List<EvidenceItem> evidenceFor(DiagnosticSignal signal) =>
      const [EvidenceItem('Connectivity', 'Offline')];
}

class ServerTimeoutRule extends DiagnosticRule {
  const ServerTimeoutRule();

  @override
  String get name => 'network.serverTimeout';

  @override
  bool matches(DiagnosticSignal signal) {
    final error = signal.error;
    return error is DioException &&
        (error.type == DioExceptionType.receiveTimeout ||
            error.type == DioExceptionType.sendTimeout);
  }

  @override
  DiagnosticCause apply(DiagnosticSignal signal) => const DiagnosticCause(
        description: 'The request reached the network but the server took too '
            'long to respond. The local write this was syncing already stands — '
            'this only affects the sync indicator.',
        confidence: DiagnosticConfidence.medium,
      );
}

class ServerErrorRule extends DiagnosticRule {
  const ServerErrorRule();

  @override
  String get name => 'network.serverError';

  @override
  bool matches(DiagnosticSignal signal) {
    final error = signal.error;
    final status = error is DioException ? error.response?.statusCode : null;
    return status != null && status >= 500;
  }

  @override
  DiagnosticCause apply(DiagnosticSignal signal) {
    final status = (signal.error as DioException).response?.statusCode;
    return DiagnosticCause(
      description: 'The server returned an error (HTTP $status) while processing '
          'this request.',
      confidence: DiagnosticConfidence.medium,
    );
  }

  @override
  List<EvidenceItem> evidenceFor(DiagnosticSignal signal) {
    final status = (signal.error as DioException).response?.statusCode;
    return [EvidenceItem('HTTP status', '$status')];
  }
}

class GenericNetworkFailureRule extends DiagnosticRule {
  const GenericNetworkFailureRule();

  @override
  String get name => 'network.generic';

  @override
  bool matches(DiagnosticSignal signal) => signal.error is DioException;

  @override
  DiagnosticCause apply(DiagnosticSignal signal) {
    final error = signal.error as DioException;
    final status = error.response?.statusCode;
    return DiagnosticCause(
      description: status == null
          ? 'A network request failed before a response was received.'
          : 'A network request failed with an unexpected response (HTTP $status).',
      confidence: DiagnosticConfidence.low,
    );
  }
}

const List<DiagnosticRule> networkRules = [
  OfflineBeforeResponseRule(),
  ServerTimeoutRule(),
  ServerErrorRule(),
  GenericNetworkFailureRule(),
];
