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
    final message = error.toString();
    final lower = message.toLowerCase();
    if (lower.contains('no server identity') ||
        lower.contains('has not synced') ||
        lower.contains('cannot sync before') ||
        lower.contains('not ready')) {
      return SyncFailure(kind: SyncErrorKind.dependencyNotReady, message: message, cause: error);
    }
    if (lower.contains('network') || lower.contains('offline') || lower.contains('connection') || lower.contains('timeout')) {
      return SyncFailure(kind: SyncErrorKind.network, message: message, cause: error);
    }
    if (lower.contains('session expired') || lower.contains('unauthorized')) {
      return SyncFailure(kind: SyncErrorKind.authExpired, message: message, cause: error);
    }
    if (lower.contains('forbidden') || lower.contains('permission')) {
      return SyncFailure(kind: SyncErrorKind.permission, message: message, cause: error);
    }
    if (lower.contains('validation') || lower.contains('invalid')) {
      return SyncFailure(kind: SyncErrorKind.validation, message: message, cause: error);
    }
    if (lower.contains('conflict') || lower.contains('already applied')) {
      return SyncFailure(kind: SyncErrorKind.conflict, message: message, cause: error);
    }
    if (lower.contains('not found') || lower.contains('no local ')) {
      return SyncFailure(kind: SyncErrorKind.permanentNotFound, message: message, cause: error);
    }
    return SyncFailure(kind: SyncErrorKind.temporaryServer, message: message, cause: error);
  }
}
