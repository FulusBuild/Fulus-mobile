import '../../models/diagnostic_event.dart';
import '../diagnostic_rule.dart';
import '../diagnostic_signal.dart';

/// Rules for the local Drift/SQLite layer — repository, transaction,
/// and constraint failures. Matched on the exception's own text rather
/// than a specific `SqliteException` field: SQLite's own error strings
/// ("FOREIGN KEY constraint failed", "database is locked", and so on)
/// are stable across sqlite3/drift package versions, which a specific
/// result-code field isn't guaranteed to be — see
/// DiagnosticSignal.effectiveErrorText's own header comment on the same
/// version-resilience tradeoff.
class ForeignKeyViolationRule extends DiagnosticRule {
  const ForeignKeyViolationRule();

  @override
  String get name => 'database.foreignKeyViolation';

  @override
  bool matches(DiagnosticSignal signal) {
    final text = signal.effectiveErrorText.toLowerCase();
    return text.contains('foreign key constraint failed') || text.contains('foreign key');
  }

  @override
  DiagnosticCause apply(DiagnosticSignal signal) => const DiagnosticCause(
        description: 'A record this operation referenced no longer exists in the '
            'local database (for example, a product removed or archived while '
            'still referenced elsewhere).',
        confidence: DiagnosticConfidence.high,
      );

  @override
  List<EvidenceItem> evidenceFor(DiagnosticSignal signal) =>
      const [EvidenceItem('Database constraint', 'FOREIGN KEY')];
}

class UniqueConstraintViolationRule extends DiagnosticRule {
  const UniqueConstraintViolationRule();

  @override
  String get name => 'database.uniqueConstraintViolation';

  @override
  bool matches(DiagnosticSignal signal) =>
      signal.effectiveErrorText.toLowerCase().contains('unique constraint failed');

  @override
  DiagnosticCause apply(DiagnosticSignal signal) => const DiagnosticCause(
        description: 'This would have created a duplicate value in a field that '
            'must be unique on this device (for example, a SKU or barcode already '
            'in use).',
        confidence: DiagnosticConfidence.high,
      );

  @override
  List<EvidenceItem> evidenceFor(DiagnosticSignal signal) =>
      const [EvidenceItem('Database constraint', 'UNIQUE')];
}

class NotNullConstraintRule extends DiagnosticRule {
  const NotNullConstraintRule();

  @override
  String get name => 'database.notNullConstraint';

  @override
  bool matches(DiagnosticSignal signal) =>
      signal.effectiveErrorText.toLowerCase().contains('not null constraint failed');

  @override
  DiagnosticCause apply(DiagnosticSignal signal) => const DiagnosticCause(
        description: 'A required field was left empty when writing to the local '
            'database.',
        confidence: DiagnosticConfidence.high,
      );

  @override
  List<EvidenceItem> evidenceFor(DiagnosticSignal signal) =>
      const [EvidenceItem('Database constraint', 'NOT NULL')];
}

class DatabaseLockedRule extends DiagnosticRule {
  const DatabaseLockedRule();

  @override
  String get name => 'database.locked';

  @override
  bool matches(DiagnosticSignal signal) {
    final text = signal.effectiveErrorText.toLowerCase();
    return text.contains('database is locked') || text.contains('sqlite_busy');
  }

  @override
  DiagnosticCause apply(DiagnosticSignal signal) => const DiagnosticCause(
        description: 'The local database was busy with another operation at the '
            'same moment. This usually resolves on its own; it is worth checking '
            'whether it happens repeatedly for the same action.',
        confidence: DiagnosticConfidence.medium,
      );
}

class DiskFullRule extends DiagnosticRule {
  const DiskFullRule();

  @override
  String get name => 'database.diskFull';

  @override
  bool matches(DiagnosticSignal signal) {
    final text = signal.effectiveErrorText.toLowerCase();
    return text.contains('sqlite_full') || text.contains('database or disk is full');
  }

  @override
  DiagnosticCause apply(DiagnosticSignal signal) => const DiagnosticCause(
        description: 'The device has run out of storage space, so the local '
            'database could not be written to.',
        confidence: DiagnosticConfidence.high,
      );
}

class DatabaseIOErrorRule extends DiagnosticRule {
  const DatabaseIOErrorRule();

  @override
  String get name => 'database.ioError';

  @override
  bool matches(DiagnosticSignal signal) {
    final text = signal.effectiveErrorText.toLowerCase();
    return text.contains('disk i/o error') ||
        text.contains('sqlite_ioerr') ||
        text.contains('unable to open database file');
  }

  @override
  DiagnosticCause apply(DiagnosticSignal signal) => const DiagnosticCause(
        description: "Fulus couldn't read or write its local database file. This "
            'usually means the device is very low on storage or the file has '
            'become inaccessible.',
        confidence: DiagnosticConfidence.medium,
      );
}

/// Catches everything else that is clearly a Drift/SQLite failure (by
/// exception type or by mentioning "sqlite"/"drift" in its own text)
/// but didn't match a more specific rule above — still tells a
/// developer "this was the database layer", just without a specific
/// mechanism, which is honestly what the evidence supports at that
/// point.
class GenericDatabaseFailureRule extends DiagnosticRule {
  const GenericDatabaseFailureRule();

  @override
  String get name => 'database.generic';

  @override
  bool matches(DiagnosticSignal signal) {
    final type = signal.exceptionType.toLowerCase();
    final text = signal.effectiveErrorText.toLowerCase();
    return type.contains('sqlite') ||
        type.contains('drift') ||
        text.contains('sqliteexception') ||
        text.contains('constraint failed');
  }

  @override
  DiagnosticCause apply(DiagnosticSignal signal) => const DiagnosticCause(
        description: 'A local database operation failed. See the technical '
            'details below for the exact error.',
        confidence: DiagnosticConfidence.low,
      );
}

const List<DiagnosticRule> databaseRules = [
  ForeignKeyViolationRule(),
  UniqueConstraintViolationRule(),
  NotNullConstraintRule(),
  DatabaseLockedRule(),
  DiskFullRule(),
  DatabaseIOErrorRule(),
  GenericDatabaseFailureRule(),
];
