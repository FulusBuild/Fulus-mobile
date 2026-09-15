import 'package:drift/drift.dart';
import 'package:ulid/ulid.dart';

import '../../domain/entities/sale_canonical_state.dart';
import '../../domain/repositories/sale_canonical_repository.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';

class SaleCanonicalRepositoryImpl implements SaleCanonicalRepository {
  SaleCanonicalRepositoryImpl({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  @override
  Future<void> reconcileServerState(SaleCanonicalState state) async {
    await _db.transaction(() async {
      final location = await (_db.select(_db.locations)
            ..where((l) => l.serverId.equals(state.locationServerId)))
          .getSingleOrNull();
      if (location == null) {
        throw StateError(
          'Canonical sale ${state.serverId} references unknown location ${state.locationServerId}.',
        );
      }

      final customerLocalId = state.customerServerId == null
          ? null
          : (await (_db.select(_db.customers)
                    ..where((c) => c.serverId.equals(state.customerServerId!)))
                .getSingleOrNull())
              ?.localId;
      if (state.customerServerId != null && customerLocalId == null) {
        throw StateError(
          'Canonical sale ${state.serverId} references unknown customer ${state.customerServerId}.',
        );
      }

      final productLocalIds = <String, String>{};
      for (final item in state.items) {
        final product = await (_db.select(_db.products)
              ..where((p) => p.serverId.equals(item.productServerId)))
            .getSingleOrNull();
        if (product == null) {
          throw StateError(
            'Canonical sale ${state.serverId} references unknown product ${item.productServerId}.',
          );
        }
        productLocalIds[item.productServerId] = product.localId;
      }

      final existing = await (_db.select(_db.sales)
            ..where((s) => s.serverId.equals(state.serverId)))
          .getSingleOrNull();
      final localId = existing?.localId ?? Ulid().toString();
      final cashierUserId = state.cashierUserId == null
          ? null
          : (await (_db.select(_db.users)
                    ..where((u) => u.localId.equals(state.cashierUserId!)))
                .getSingleOrNull())
              ?.localId;

      if (existing == null) {
        await _db.into(_db.sales).insert(
              SalesCompanion.insert(
                localId: localId,
                serverId: Value(state.serverId),
                clientReference: state.clientReference.isEmpty
                    ? state.serverId
                    : state.clientReference,
                invoiceNumber: Value(state.invoiceNumber),
                customerId: Value(customerLocalId),
                locationId: location.localId,
                cashierUserId: Value(cashierUserId),
                saleDate: state.saleDate,
                subtotal: state.subtotal,
                wholeCartDiscount: const Value(0),
                discount: Value(state.discount),
                tax: Value(state.tax),
                total: state.total,
                amountPaid: Value(state.amountPaid),
                paymentMethod: Value(state.paymentMethod),
                notes: Value(state.notes),
                createdAt: state.createdAt,
                updatedAt: state.updatedAt,
                deletedAt: Value(state.deletedAt),
                syncStatus: SyncStatus.settled,
              ),
            );
      } else {
        await (_db.update(_db.sales)..where((s) => s.localId.equals(localId))).write(
          SalesCompanion(
            serverId: Value(state.serverId),
            clientReference: Value(state.clientReference.isEmpty
                ? state.serverId
                : state.clientReference),
            invoiceNumber: Value(state.invoiceNumber),
            customerId: Value(customerLocalId),
            locationId: Value(location.localId),
            cashierUserId: Value(cashierUserId),
            saleDate: Value(state.saleDate),
            subtotal: Value(state.subtotal),
            discount: Value(state.discount),
            tax: Value(state.tax),
            total: Value(state.total),
            amountPaid: Value(state.amountPaid),
            paymentMethod: Value(state.paymentMethod),
            notes: Value(state.notes),
            updatedAt: Value(state.updatedAt),
            deletedAt: Value(state.deletedAt),
            syncStatus: const Value(SyncStatus.settled),
          ),
        );
      }

      await (_db.delete(_db.saleItems)..where((i) => i.saleLocalId.equals(localId))).go();
      await (_db.delete(_db.salePayments)..where((p) => p.saleLocalId.equals(localId))).go();

      for (final item in state.items) {
        await _db.into(_db.saleItems).insert(
              SaleItemsCompanion.insert(
                localId: Ulid().toString(),
                saleLocalId: localId,
                productLocalId: Value(productLocalIds[item.productServerId]),
                description: const Value(''),
                quantity: item.quantity,
                unitPrice: item.unitPrice,
                costPriceAtSale: item.costPriceAtSale,
                lineDiscount: const Value(0),
              ),
            );
      }

      for (final payment in state.payments) {
        await _db.into(_db.salePayments).insert(
              SalePaymentsCompanion.insert(
                localId: Ulid().toString(),
                saleLocalId: localId,
                method: payment.method,
                amount: payment.amount,
                recordedAt: payment.recordedAt,
              ),
            );
      }
    });
  }

  @override
  Future<void> reconcileDeleted(String serverId) async {
    final row = await (_db.select(_db.sales)
          ..where((s) => s.serverId.equals(serverId)))
        .getSingleOrNull();
    if (row == null) return;
    final now = DateTime.now();
    await (_db.update(_db.sales)..where((s) => s.localId.equals(row.localId))).write(
      SalesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        syncStatus: const Value(SyncStatus.settled),
      ),
    );
  }
}
