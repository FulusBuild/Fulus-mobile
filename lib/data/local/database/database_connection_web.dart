import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:flutter/foundation.dart';

Future<String> resolveDatabaseFilePath() async => 'fulus_mobile.sqlite';

DatabaseConnection openDatabaseConnection() {
  return DatabaseConnection.delayed(Future(() async {
    final result = await WasmDatabase.open(
      databaseName: 'fulus_mobile',
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.js'),
    );

    if (result.missingFeatures.isNotEmpty) {
      debugPrint(
        'Fulus Web database using ${result.chosenImplementation}; '
        'missing browser features: ${result.missingFeatures}',
      );
    }

    return result.resolvedExecutor;
  }));
}
