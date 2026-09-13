import 'package:drift/drift.dart';

import '../../domain/entities/auth_user.dart';
import '../../domain/entities/business_settings.dart';
import '../local/database/database.dart';
import 'cloud_restore_importer.dart';

/// Coordinates the parts of reinstall recovery that must happen around the
/// existing transactional data importer.
///
/// The importer owns the destructive business-data transaction. This
/// coordinator ensures the cloud settings are available before local mutation,
/// imports the owner identity so owner-referenced rows satisfy local FKs, and
/// creates the local session only after the import has verified integrity.
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

    // The caller fetched this before entering the destructive phase. Persist
    // it now so a settings outage cannot occur halfway through the restore.
    await _replaceSettings(settings);

    try {
      // Import the authenticated identity too. The previous flow skipped it
      // and created the owner afterward, which could leave sales/audit rows
      // pointing at a user that did not exist during FK verification.
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
      // CloudRestoreImporter is itself transactional. Restore the settings
      // row as the compensating operation for the small pre-import settings
      // transaction so a failed restore does not strand onboarding state.
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

      // The generic staff importer creates an Employee row for every cloud
      // membership. The owner is a local identity, not an employee, so remove
      // that synthetic employee row before exposing the restored session.
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
