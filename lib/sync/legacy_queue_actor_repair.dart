import 'package:drift/drift.dart';

import '../data/local/database/database.dart';

/// Repairs durable queue rows written by versions that predate actor
/// attribution. This is migration/repair knowledge, not sync-runtime policy.
/// Keeping it here prevents the generic queue-draining engine from knowing
/// which business tables can provide an actor for each legacy entity type.
class LegacyQueueActorRepair {
  LegacyQueueActorRepair(this._db, {this.actorUserIdProvider});

  final AppDatabase _db;
  final String? Function()? actorUserIdProvider;

  Future<void> repair() async {
    final rows = await (_db.select(_db.syncQueueItems)
          ..where((q) => q.actorUserId.isNull()))
        .get();
    if (rows.isEmpty) return;

    // The fallback must be the cloud/Supabase actor namespace. Do not\n    // derive it from Users.localId: local identities are ULIDs for owner\n    // accounts and are not valid keys for scoped cloud refresh credentials.\n    final fallbackActor = actorUserIdProvider?.call();
    await _db.transaction(() async {
      for (final item in rows) {
        String? actor;
        switch (item.entityType) {
          case 'sale':
            actor = (await (_db.select(_db.sales)
                  ..where((r) => r.localId.equals(item.entityLocalId)))
                .getSingleOrNull())
                ?.cashierUserId;
            break;
          case 'cash_drawer_shift':
            actor = (await (_db.select(_db.cashDrawerShifts)
                  ..where((r) => r.localId.equals(item.entityLocalId)))
                .getSingleOrNull())
                ?.cashierUserId;
            break;
          case 'return':
            final request = await (_db.select(_db.returnRequests)
                  ..where((r) => r.localId.equals(item.entityLocalId)))
                .getSingleOrNull();
            if (request != null) {
              actor = (await (_db.select(_db.sales)
                    ..where((r) =>
                        r.localId.equals(request.originalSaleLocalId)))
                  .getSingleOrNull())
                  ?.cashierUserId;
            }
            break;
          case 'customer_ledger':
            final entry = await (_db.select(_db.customerLedgerEntries)
                  ..where((r) => r.localId.equals(item.entityLocalId)))
                .getSingleOrNull();
            if (entry?.saleLocalId != null) {
              actor = (await (_db.select(_db.sales)
                    ..where((r) => r.localId.equals(entry!.saleLocalId!)))
                  .getSingleOrNull())
                  ?.cashierUserId;
            }
            break;
        }

        actor ??= fallbackActor;
        if (actor != null && actor.isNotEmpty) {
          await (_db.update(_db.syncQueueItems)
                ..where((q) => q.id.equals(item.id)))
              .write(SyncQueueItemsCompanion(actorUserId: Value(actor)));
        }
      }
    });
  }
}
