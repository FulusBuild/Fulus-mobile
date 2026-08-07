import '../../../domain/repositories/database_lifecycle.dart';
import 'database.dart';

/// The concrete `AppDatabase`-backed `DatabaseLifecycle` INTEGRATION.md
/// asked for — used only by `BackupRepositoryImpl` (Stage 10) to close
/// the live connection before a restore overwrites the file, then get a
/// working connection back afterward.
///
/// IMPORTANT, found while actually wiring this rather than templating
/// it: [reopenAfterMaintenance] can only give the app *a* fresh,
/// working `AppDatabase` — it cannot make every repository already
/// holding a direct reference to the OLD instance (SaleRepositoryImpl,
/// CustomerRepositoryImpl, every other repository bootstrap.dart
/// constructed with `database` passed directly in) start using the new
/// one instead. Those references were captured at construction time,
/// not looked up reactively, so nothing short of reconstructing the
/// entire DI graph — every repository, every sync handler, the whole
/// of bootstrap.dart's return value — actually achieves a true
/// mid-session hot-swap. That's a real, separate piece of work (making
/// `AppDatabase` itself swappable behind a stable indirection everything
/// depends on instead of a direct reference), not something this class
/// can paper over by itself.
///
/// So: this class does the part that's genuinely safe and correct on
/// its own (close the connection so the file can be overwritten without
/// risking corruption; open a new, working connection to whatever is
/// there afterward, so the app is never left with zero working
/// connection) and is honest about the rest. The correct, honest UX for
/// BackupRepositoryImpl.restore's caller (a future Settings screen) is
/// to prompt the user to restart the app once restore succeeds — the
/// same pattern most apps use for exactly this class of operation — not
/// to claim the restored data is live everywhere without one.
/// [onReopened] exists so bootstrap.dart can update whatever it wants
/// with the fresh instance (e.g. the value backing databaseProvider,
/// for anything constructed AFTER a restart that reads it fresh) without
/// this class needing to know about ProviderContainer or Riverpod at
/// all.
class AppDatabaseLifecycle implements DatabaseLifecycle {
  AppDatabaseLifecycle({
    required AppDatabase Function() getDatabase,
    required void Function(AppDatabase) onReopened,
  })  : _getDatabase = getDatabase,
        _onReopened = onReopened;

  final AppDatabase Function() _getDatabase;
  final void Function(AppDatabase) _onReopened;

  @override
  Future<String> currentDatabasePath() => AppDatabase.resolveDatabasePath();

  @override
  Future<void> closeForMaintenance() => _getDatabase().close();

  @override
  Future<void> reopenAfterMaintenance() async {
    // A fresh instance, not the closed one — a closed Drift database
    // can't be reused. See this class's own doc comment for why this
    // being "the app's working database again" is not the same claim as
    // "every existing repository now uses it."
    final fresh = AppDatabase.open();
    _onReopened(fresh);
  }
}
