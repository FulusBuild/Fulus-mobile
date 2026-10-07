/// Stable classification for sync failures. The queue engine uses this
/// classification to decide whether an item should retry automatically or be
/// surfaced for attention; UI never has to infer transport semantics from a
/// raw exception string.
enum SyncErrorKind {
  network,
  temporaryServer,
  authExpired,
  permission,
  validation,
  conflict,
  dependencyNotReady,
  permanentNotFound,
}

class SyncFailure implements Exception {
  const SyncFailure({required this.kind, required this.message, this.cause});

  final SyncErrorKind kind;
  final String message;
  final Object? cause;

  bool get shouldRetry =>
      kind == SyncErrorKind.network ||
      kind == SyncErrorKind.temporaryServer ||
      kind == SyncErrorKind.dependencyNotReady;

  @override
  String toString() => 'SyncFailure(${kind.name}): $message';

  static SyncFailure classify(Object error) {
    if (error is SyncFailure) return error;

    // Preserve the application's typed failure contract before looking at
    // human-readable exception text. Transport and business layers already
    // expose stable failure types/codes; sync should not reverse-engineer
    // retry semantics from words such as "invalid" or "permission".
    if (error is NetworkFailure) {
      return SyncFailure(
        kind: SyncErrorKind.network,
        message: error.message,
        cause: error,
      );
    }
    if (error is AuthFailure) {
      return SyncFailure(
        kind: SyncErrorKind.authExpired,
        message: error.message,
        cause: error,
      );
    }
    if (error is ValidationFailure) {
      return SyncFailure(
        kind: SyncErrorKind.validation,
        message: error.message,
        cause: error,
      );
    }
    if (error is BusinessRuleFailure) {
      final code = error.code?.toUpperCase();
      final conflict = code == 'IDEMPOTENCY_CONFLICT' ||
          code == 'SYNC_CONFLICT' ||
          code == 'CONFLICT';
      return SyncFailure(
        kind: conflict
            ? SyncErrorKind.conflict
            : SyncErrorKind.validation,
        message: error.message,
        cause: error,
      );
    }

    // A small compatibility mapping remains for legacy internal readiness
    // failures that predate the typed SyncFailure boundary. These are exact
    // phrases owned by Fulus code, not generic substring guesses.
    final message = error.toString();
    if (message == 'No server identity available.' ||
        message == 'Cannot sync before cloud readiness is established.' ||
        message == 'Fulus Cloud is not ready for canonical pull.') {
      return SyncFailure(
        kind: SyncErrorKind.dependencyNotReady,
        message: message,
        cause: error,
      );
    }

    // Unknown failures are deliberately retryable rather than permanently
    // classified from arbitrary exception wording. The queue engine can
    // surface repeated failures through its normal attention threshold.
    return SyncFailure(
      kind: SyncErrorKind.temporaryServer,
      message: message,
      cause: error,
    );
  }
}
