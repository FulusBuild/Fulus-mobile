import 'dart:async';

/// Default upper bound for an async operation that is expected to resolve
/// quickly enough to keep a screen from appearing permanently stuck.
const fulusLoadingTimeout = Duration(seconds: 12);

extension FulusStreamTimeout<T> on Stream<T> {
  /// Converts a stream that never emits into a recoverable error state.
  Stream<T> withFulusLoadingTimeout({Duration timeout = fulusLoadingTimeout}) {
    return this.timeout(
      timeout,
      onTimeout: (sink) => sink.addError(
        TimeoutException('Loading took too long'),
      ),
    );
  }
}

extension FulusFutureTimeout<T> on Future<T> {
  Future<T> withFulusLoadingTimeout({Duration timeout = fulusLoadingTimeout}) {
    return this.timeout(timeout);
  }
}
