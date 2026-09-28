import 'dart:async';

/// Default upper bound for an async operation that is expected to resolve
/// quickly enough to keep a screen from appearing permanently stuck.
const fulusLoadingTimeout = Duration(seconds: 12);

extension FulusStreamTimeout<T> on Stream<T> {
  /// Bounds only the initial data emission.
  ///
  /// A live local-data stream is expected to remain quiet after its first
  /// snapshot. Using Stream.timeout() directly would incorrectly turn a
  /// healthy, unchanged stream into a timeout error after [timeout]. This
  /// wrapper instead fails only when the first snapshot never arrives.
  Stream<T> withFulusLoadingTimeout({
    Duration timeout = fulusLoadingTimeout,
  }) {
    return Stream.multi((controller) {
      var receivedFirstEvent = false;
      Timer? timer;
      StreamSubscription<T>? subscription;

      void failInitialLoad() {
        if (receivedFirstEvent || controller.isClosed) return;
        controller.addError(
          TimeoutException('Loading took too long', timeout),
        );
        controller.close();
        unawaited(subscription?.cancel());
      }

      timer = Timer(timeout, failInitialLoad);
      subscription = this.listen(
        (event) {
          if (!receivedFirstEvent) {
            receivedFirstEvent = true;
            timer?.cancel();
            timer = null;
          }
          controller.add(event);
        },
        onError: (Object error, StackTrace stackTrace) {
          controller.addError(error, stackTrace);
        },
        onDone: () {
          timer?.cancel();
          timer = null;
          controller.close();
        },
      );

      controller.onCancel = () async {
        timer?.cancel();
        timer = null;
        await subscription?.cancel();
      };
    });
  }
}

extension FulusFutureTimeout<T> on Future<T> {
  Future<T> withFulusLoadingTimeout({Duration timeout = fulusLoadingTimeout}) {
    return this.timeout(timeout);
  }
}
