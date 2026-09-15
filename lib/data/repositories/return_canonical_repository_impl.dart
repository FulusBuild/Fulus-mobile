import 'package:drift/drift.dart';
import 'package:ulid/ulid.dart';

import '../../domain/entities/return_canonical_state.dart';
import '../../domain/repositories/return_canonical_repository.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';

class ReturnCanonicalRepositoryImpl implements ReturnCanonicalRepository {
  ReturnCanonicalRepositoryImpl({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  @override
  Future<void> reconcileServerState(ReturnCanonicalState state) async {
    await _db.transaction(() async {
      final sale = await (_db.select(_db.sales)
            ..where((s) => s.serverId.equals(state.originalSaleServerId)))
          .getSingleOrNull();
      if (sale == null) {
        throw StateError(
          'Canonical return ${state.serverId} references unknown sale ${state.originalSaleServerId}.',
        );
      }

      final productLocalIds = <String, String>{};
      for (final item in state.items) {
        final product = await (_db.select(_db.products)
              ..where((p) => p.serverId.equals(item.productServerId)))
            .getSingleOrNull();
        if (product == null) {
          throw StateError(
            'Canonical return ${state.serverId} references unknown product ${item.productServerId}.',
          );
        }
        productLocalIds[item.productServerId] = product.localId;
      }

      final existing = await (_db.select(_db.returnRequests)
            ..where((r) => r.serverId.equals(state.serverId)))
          .getSingleOrNull();
      final localId = existing?.localId ?? Ulid().toString();
      final isVoid = existing?.isVoid ?? state.isVoid;

      if (existing == null) {
        await _db.into(_db.returnRequests).insert(
              ReturnRequestsCompanion.insert(
                localId: localId,
                serverId: Value(state.serverId),
                originalSaleLocalId: sale.localId,
                status: state.status,
                returnReason: state.returnReason,
                refundAmount: state.refundAmount,
                refundMethod: state.refundMethod,
                inventoryRestored: Value(state.inventoryRestored),
                isVoid: Value(isVoid),
                createdAt: state.createdAt,
                updatedAt: state.updatedAt,
                completedAt: Value(state.completedAt),
                syncStatus: SyncStatus.settled,
              ),
            );
      } else {
        await (_db.update(_db.returnRequests)..where((r) => r.localId.equals(localId))).write(
          ReturnRequestsCompanion(
            serverId: Value(state.serverId),
            originalSaleLocalId: Value(sale.localId),
            status: Value(state.status),
            returnReason: Value(state.returnReason),
            refundAmount: Value(state.refundAmount),
            refundMethod: Value(state.refundMethod),
            inventoryRestored: Value(state.inventoryRestored),
            updatedAt: Value(state.updatedAt),
            completedAt: Value(state.completedAt),
            syncStatus: const Value(SyncStatus.settled),
          ),
        );
      }

      await (_db.delete(_db.returnItems)..where((i) => i.returnLocalId.equals(localId))).go();
      for (final item in state.items) {
        await _db.into(_db.returnItems).insert(
              ReturnItemsCompanion.insert(
                localId: Ulid().toString(),
                returnLocalId: localId,
                productLocalId: productLocalIds[item.productServerId]!,
                quantity: item.quantity,
              ),
            );
      }
    });
  }

  @override
  Future<void> reconcileDeleted(String serverId) async {
    final row = await (_db.select(_db.returnRequests)
          ..where((r) => r.serverId.equals(serverId)))
        .getSingleOrNull();
    if (row == null) return;
    final now = DateTime.now();
    await (_db.update(_db.returnRequests)..where((r) => r.localId.equals(row.localId))).write(
      ReturnRequestsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        syncStatus: const Value(SyncStatus.settled),
      ),
    );
  }
}
