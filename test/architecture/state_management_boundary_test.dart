import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('flutter_bloc remains confined to the Sell feature boundary', () {
    final lib = Directory('lib');
    final violations = <String>[];

    if (!lib.existsSync()) {
      fail('Expected the repository lib/ directory to exist.');
    }

    for (final entity in lib.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final normalized = entity.path.replaceAll('\\', '/');
      if (normalized.contains('/features/sell/')) continue;

      final source = entity.readAsStringSync();
      if (source.contains("package:flutter_bloc/flutter_bloc.dart")) {
        violations.add(normalized);
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'The benchmark permits flutter_bloc/Cubit only inside the Sell cart boundary.',
    );
  });
}
