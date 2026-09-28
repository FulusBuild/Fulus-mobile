import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../../../lib/core/utils/async_timeout.dart';

void main() {
  test('times out when a stream never emits its first event', () async {
    final stream = const Stream<int>.empty().asyncExpand(
      (_) => const Stream<int>.empty(),
    );

    await expectLater(
      stream.withFulusLoadingTimeout(
        timeout: const Duration(milliseconds: 20),
      ),
      emitsError(isA<TimeoutException>()),
    );
  });

  test('does not time out a healthy stream after its first event', () async {
    final controller = StreamController<int>();
    addTearDown(controller.close);

    final events = <int>[];
    final subscription = controller.stream
        .withFulusLoadingTimeout(
          timeout: const Duration(milliseconds: 20),
        )
        .listen(events.add);

    controller.add(1);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    controller.add(2);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await subscription.cancel();

    expect(events, [1, 2]);
  });
}
