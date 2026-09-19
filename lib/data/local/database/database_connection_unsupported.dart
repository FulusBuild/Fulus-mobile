import 'package:drift/drift.dart';

QueryExecutor openDatabaseConnection() {
  throw UnsupportedError('No supported database connection for this platform.');
}

Future<String> resolveDatabaseFilePath() async {
  throw UnsupportedError('No supported database path for this platform.');
}
