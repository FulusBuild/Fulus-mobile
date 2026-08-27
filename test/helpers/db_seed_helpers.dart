import 'package:drift/drift.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:fulus_mobile/domain/entities/auth_user.dart';

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

/// Seeds a single user row and returns its localId. `Sales.
/// cashierUserId` and other FKs reference `users(local_id)`, so any
/// test that attributes a row to a signed-in user needs a matching
/// row here first, or the insert fails with a FOREIGN KEY constraint
/// error.
///
/// Defaults to `user-cashier-1`, the id most repository tests'
/// `_FakeAuthRepository`/cashier fixtures reference.
Future<String> seedUser(
  AppDatabase db, {
  String localId = 'user-cashier-1',
  String username = 'cashier1',
  String email = 'cashier1@test.local',
  String fullName = 'Test Cashier',
  AuthRole role = AuthRole.employee,
}) async {
  await db.into(db.users).insert(
        UsersCompanion.insert(
          localId: localId,
          username: Value(username),
          email: Value(email),
          fullName: fullName,
          hashedPassword: const Value('irrelevant-for-this-test'),
          passwordSalt: const Value('irrelevant-for-this-test'),
          role: role,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      );
  return localId;
}

/// Seeds a minimal, self-contained sale row and returns its localId.
/// `CustomerLedgerEntries.saleLocalId` and other FKs reference
/// `sales(local_id)`, so any test that links a row to a sale by id
/// (without exercising SaleRepositoryImpl itself) needs a matching
/// row here first.
///
/// Seeds its own parent [locationId] row via [seedLocation] unless one
/// already exists with that id — safe to call multiple times with the
/// same [locationId] across several `seedSale` calls in one test.
Future<String> seedSale(
  AppDatabase db, {
  String localId = 'sale-1',
  String locationId = 'loc-1',
  String? cashierUserId,
  double subtotal = 1000,
  double total = 1000,
  double amountPaid = 1000,
}) async {
  final existingLocation = await (db.select(db.locations)
        ..where((l) => l.localId.equals(locationId)))
      .getSingleOrNull();
  if (existingLocation == null) {
    await seedLocation(db, localId: locationId);
  }

  final now = DateTime(2026, 1, 1);
  await db.into(db.sales).insert(
        SalesCompanion.insert(
          localId: localId,
          clientReference: localId,
          locationId: locationId,
          cashierUserId: Value(cashierUserId),
          saleDate: now,
          subtotal: subtotal,
          total: total,
          amountPaid: Value(amountPaid),
          createdAt: now,
          updatedAt: now,
          syncStatus: SyncStatus.settled,
        ),
      );
  return localId;
}

/// Runs [body] with SQLite's FK enforcement temporarily switched off,
/// restoring it afterward even if [body] throws. For the rare test
/// that deliberately constructs a dangling reference (e.g. a
/// `cashierUserId` pointing at a user record that no longer exists) to
/// verify the app handles that state gracefully — real FK-enforced
/// inserts can't produce that state directly, but data migrated from
/// an older schema or a deleted-but-still-referenced row can, so it's
/// worth testing against.
Future<void> withoutForeignKeyChecks(
  AppDatabase db,
  Future<void> Function() body,
) async {
  await db.customStatement('PRAGMA foreign_keys = OFF');
  try {
    await body();
  } finally {
    await db.customStatement('PRAGMA foreign_keys = ON');
  }
}
