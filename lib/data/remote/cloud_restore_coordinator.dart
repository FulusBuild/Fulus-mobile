import 'package:drift/drift.dart';

import '../../domain/entities/business_settings.dart';
import '../local/database/database.dart';
import 'cloud_restore_importer.dart';

/// Coordinates the parts of reinstall recovery that must happen around the
/// existing transactional data importer.
///
/// The importer intentionally owns the destructive business-data transaction.
/// This coordinator makes sure the two pieces it needs in order to satisfy
/// local foreign keys (the owner identity) and onboarding (business settings)
/// exist before the import, while restoring the previous settings if the
/// destructive import fails.
class CloudRestoreCoordinator {
  CloudRestoreCoordinator(this._db);

  final AppDatabase _db;

  Future<CloudRestoreResult> restore({
    required Map<String, dynamic> snapshot,
    required String ownerCloudUserId,
    required String ownerEmail,
    required BusinessSettingsResponseDto settings,
  }) async {
    final previousSettings =
        await (_db.select(_db.businessSettings)).getSingleOrNull();

    // Settings are fetched by the caller before this method is entered, so a
    // network failure cannot leave the local database half-restored. Write the
    // server copy before the destructive import and compensate if import
    // fails; the import itself remains the authoritative atomic boundary.
    await _replaceSettings(settings);

    try {
      // The existing importer historically skipped the owner because the
      // screen created the owner after import. That breaks FK-backed rows
      // (e.g. sales.cashier_user_id and audit actors) during verification.
      // Import the authenticated identity too; it is normalized to owner
      // immediately below.
      final result = await CloudRestoreImporter(_db).importSnapshot(
        snapshot,
        ownerCloudUserId: null,
      );

      await _normalizeOwner(
        ownerCloudUserId: ownerCloudUserId,
        ownerEmail: ownerEmail,
        snapshot: snapshot,
      );

      return result;
    } catch (_) {
      await _restorePreviousSettings(previousSettings);
      rethrow;
    }
  }

  Future<void> _replaceSettings(BusinessSettingsResponseDto settings) async {
    await _db.transaction(() async {
      await _db.delete(_db.businessSettings).go();
      await _db.into(_db.businessSettings).insert(settings.toDriftCompanion());
    });
  }

  Future<void> _restorePreviousSettings(BusinessSettingRow? previous) async {
    await _db.transaction(() async {
      await _db.delete(_db.businessSettings).go();
      if (previous == null) return;
      await _db.into(_db.businessSettings).insert(
            BusinessSettingsCompanion.insert(
              id: previous.id,
              businessName: previous.businessName,
              address: Value(previous.address),
              phone: Value(previous.phone),
              email: Value(previous.email),
              tin: Value(previous.tin),
              currencySymbol: Value(previous.currencySymbol),
              vatEnabled: previous.vatEnabled,
              vatRate: previous.vatRate,
              receiptFooter: Value(previous.receiptFooter),
              updatedAt: previous.updatedAt,
            ),
          );
    });
  }

  Future<void> _normalizeOwner({
    required String ownerCloudUserId,
    required String ownerEmail,
    required Map<String, dynamic> snapshot,
  }) async {
    final profile = snapshot['profile'];
    final profileName = profile is Map
        ? profile['full_name']?.toString().trim()
        : null;
    final fullName = profileName?.isNotEmpty == true ? profileName! : 'Owner';

    await _db.transaction(() async {
      final owner = await (_db.select(_db.users)
            ..where((u) => u.localId.equals(ownerCloudUserId)))
          .getSingleOrNull();
      if (owner == null) {
        throw StateError('Restore did not create the cloud owner identity.');
      }

      await (_db.update(_db.users)
            ..where((u) => u.localId.equals(ownerCloudUserId)))
          .write(
        UsersCompanion(
          email: Value(ownerEmail),
          fullName: Value(fullName),
          role: const Value(AuthRole.owner),
          isActive: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // The generic staff importer creates an Employee row for every
      // membership so that all cloud identities have a local representation.
      // The owner is an identity, not an employee; remove that synthetic row.
      await (_db.delete(_db.employees)
            ..where((e) => e.authUserId.equals(ownerCloudUserId)))
          .go();

      await _db.delete(_db.sessions).go();
      await _db.into(_db.sessions).insert(
            SessionsCompanion.insert(
              id: 'current',
              userId: ownerCloudUserId,
              activeLocationId: const Value(null),
            ),
          );
    });
  }
}
