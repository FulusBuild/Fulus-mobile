import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/core/diagnostics/capture/global_error_capture.dart';

void main() {
  test('layout diagnostic component prefers the app widget name', () {
    final details = FlutterErrorDetails(
      exception: FlutterError('A RenderFlex overflowed.'),
      library: 'rendering library',
      informationCollector: () sync* {
        yield ErrorDescription(
          'The relevant error-causing widget was:\n  StockActionTile\n',
        );
      },
    );

    expect(diagnosticComponentFromFlutterError(details), 'StockActionTile');
  });

  test('returns null when Flutter supplies no actionable widget context', () {
    final details = FlutterErrorDetails(
      exception: StateError('unexpected'),
      library: 'rendering library',
    );

    expect(diagnosticComponentFromFlutterError(details), isNull);
  });
}
