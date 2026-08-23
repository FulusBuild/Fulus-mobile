/// How serious a captured DiagnosticEvent is. Deliberately four levels,
/// not two — `critical` exists separately from `error` so a developer
/// scanning the log can immediately tell "the app nearly went down" (an
/// uncaught Flutter framework error, a startup failure) apart from "one
/// operation failed but the app kept running normally" (a sale that
/// didn't complete, a sync item that needs attention). `info` is for
/// non-failure events still worth a permanent record — see
/// diagnostic_event.dart's own note on why the Diagnostics screen's
/// "Events" count can exceed Errors + Warnings.
///
/// Deliberately pure Dart, no Flutter import — this enum is used from
/// the data layer (data/local/database/tables.dart, via Drift's
/// `textEnum<T>()`), which stays Flutter-free throughout this codebase.
/// Color/icon presentation for each value lives instead in
/// features/more/diagnostics/presentation/widgets/diagnostic_style.dart,
/// as extension methods only the UI layer imports.
enum DiagnosticSeverity {
  critical,
  error,
  warning,
  info;

  /// Plain-language label — always shown alongside an icon/color in the
  /// UI, never color alone (accessibility requirement).
  String get label {
    switch (this) {
      case DiagnosticSeverity.critical:
        return 'Critical';
      case DiagnosticSeverity.error:
        return 'Error';
      case DiagnosticSeverity.warning:
        return 'Warning';
      case DiagnosticSeverity.info:
        return 'Info';
    }
  }
}

/// Which subsystem a DiagnosticEvent came from. Consolidates the (much
/// longer) list of boundaries named in the diagnostic-system brief into
/// a set small enough to be useful as a filter chip row — several named
/// boundaries share one bucket where they're diagnosed the same way
/// (e.g. repository/Drift/SQLite/transaction failures are all
/// `database`; PDF export and CSV export are both `exportReporting`).
enum DiagnosticCategory {
  /// Flutter's own framework layer — widget build/layout/paint errors
  /// reaching `FlutterError.onError`.
  flutterFramework,

  /// An unhandled Dart exception or Future error that isn't more
  /// specifically one of the categories below — the generic safety-net
  /// bucket for `PlatformDispatcher.onError`.
  dartRuntime,

  /// Repository, Drift, SQLite, and transaction failures.
  database,

  /// Dio/API failures — meaningful only for the Sync layer in this
  /// app's current architecture (see failure.dart's own header comment
  /// on why the core app no longer makes network calls at all).
  network,

  /// Local sign-in/session/permission failures.
  authentication,

  /// Sync engine, sync queue, and conflict-resolution failures.
  synchronization,

  /// File I/O — backups, receipts, photos, any on-disk read/write.
  fileSystem,

  /// PDF/CSV export generation failures.
  exportReporting,

  /// Camera, scanner, printer, and other platform-channel failures.
  platformChannel,

  /// Routing/navigation failures (a route that couldn't resolve, a
  /// missing required `extra`).
  navigation,

  /// Input/business-rule validation failures worth a permanent record
  /// (distinct from the ordinary, already-handled Failure shown inline
  /// on a form — see diagnostic_logger.dart's own header comment on
  /// that distinction).
  validation,

  /// The app's in-memory or on-disk state stopped being internally
  /// consistent (e.g. a cart referencing an item that no longer exists).
  stateConsistency,

  /// Environment/configuration problems (a missing required setting, a
  /// malformed on-device config value).
  configuration,

  /// Sale/payment/checkout failures.
  sales,

  /// Stock/inventory failures.
  inventory,

  /// Failures during app startup/initialization, before the first
  /// screen is usable.
  startup,

  /// Evidence didn't fit any of the above — never silently mis-filed
  /// into a more specific bucket just to avoid this one.
  unknown;

  String get label {
    switch (this) {
      case DiagnosticCategory.flutterFramework:
        return 'Flutter framework';
      case DiagnosticCategory.dartRuntime:
        return 'App runtime';
      case DiagnosticCategory.database:
        return 'Database';
      case DiagnosticCategory.network:
        return 'Network';
      case DiagnosticCategory.authentication:
        return 'Authentication';
      case DiagnosticCategory.synchronization:
        return 'Sync';
      case DiagnosticCategory.fileSystem:
        return 'File system';
      case DiagnosticCategory.exportReporting:
        return 'Export';
      case DiagnosticCategory.platformChannel:
        return 'Device';
      case DiagnosticCategory.navigation:
        return 'Navigation';
      case DiagnosticCategory.validation:
        return 'Validation';
      case DiagnosticCategory.stateConsistency:
        return 'App state';
      case DiagnosticCategory.configuration:
        return 'Configuration';
      case DiagnosticCategory.sales:
        return 'Sales';
      case DiagnosticCategory.inventory:
        return 'Inventory';
      case DiagnosticCategory.startup:
        return 'Startup';
      case DiagnosticCategory.unknown:
        return 'Other';
    }
  }
}

/// How sure the deterministic root-cause engine is about a
/// DiagnosticCause. `unknown` is a first-class, expected outcome, not
/// an error state — see root_cause_engine.dart's own header comment:
/// this system never invents a cause just to avoid returning `unknown`.
enum DiagnosticConfidence {
  high,
  medium,
  low,
  unknown;

  String get label {
    switch (this) {
      case DiagnosticConfidence.high:
        return 'HIGH';
      case DiagnosticConfidence.medium:
        return 'MEDIUM';
      case DiagnosticConfidence.low:
        return 'LOW';
      case DiagnosticConfidence.unknown:
        return 'UNKNOWN';
    }
  }
}

/// Where a captured event is in its own lifecycle. Today every event
/// goes captured -> stored -> (viewed) -> (shared), entirely on-device —
/// see diagnostic_event.dart's own header comment on why `pendingSync`/
/// `synced`/`syncFailed` exist here already even though nothing in this
/// phase ever sets them.
enum DiagnosticLifecycleStatus {
  captured,
  stored,
  viewed,
  shared,
  pendingSync,
  synced,
  syncFailed,
}
