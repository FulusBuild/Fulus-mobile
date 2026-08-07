import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';

/// Shared seed helpers for repository tests that run against a real
/// in-memory [AppDatabase]. Several repository tables (draft_carts,
/// sales, products, ...) carry a foreign key to `locations`, so any
/// test that inserts rows referencing a `locationId` needs a matching
/// row in `locations` first or the insert fails with a FOREIGN KEY
/// constraint error.
///
/// Centralizing this avoids every test file hand-rolling its own
/// `LocationsCompanion.insert(...)` call with slightly different
/// defaults.

/// Seeds a single location row and returns its localId.
///
/// Defaults to `loc-1`, the id most repository tests reference — call
/// with a different [localId] (e.g. `loc-2`) to seed a second,
/// distinct location for multi-location tests.
Future<String> seedLocation(
  AppDatabase db, {
  String localId = 'loc-1',
  String name = 'Main Store',
}) async {
  await db.into(db.locations).insert(
        LocationsCompanion.insert(
          localId: localId,
          name: name,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          syncStatus: SyncStatus.settled,
        ),
      );
  return localId;
}
