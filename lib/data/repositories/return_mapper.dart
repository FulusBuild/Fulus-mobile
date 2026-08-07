import 'package:drift/drift.dart';

import '../../domain/entities/return_request.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';

ReturnStatus _statusFromColumn(String value) {
  return switch (value) {
    'pending' => ReturnStatus.pending,
    'approved' => ReturnStatus.approved,
    'rejected' => ReturnStatus.rejected,
    'completed' => ReturnStatus.completed,
    _ => throw ArgumentError.value(value, 'status', 'unrecognized return status'),
  };
}

extension ReturnRequestToCompanion on ReturnRequest {
  ReturnRequestsCompanion toDriftCompanion() {
    return ReturnRequestsCompanion.insert(
      localId: localId,
      originalSaleLocalId: originalSaleLocalId,
      status: status.name,
      returnReason: returnReason,
      refundAmount: refundAmount,
      refundMethod: refundMethod,
      createdAt: createdAt,
      updatedAt: updatedAt,
      syncStatus: SyncStatus.pending,
      serverId: Value(serverId),
      inventoryRestored: Value(inventoryRestored),
      completedAt: Value(completedAt),
    );
  }

  /// **No `clientReference`** — see `ReturnCreateDto`'s own doc comment
  /// for the confirmed gap.
  ReturnCreateDto toCreateDto() {
    return ReturnCreateDto(
      originalSaleId: originalSaleLocalId,
      items: items
          .map((i) => ReturnItemDto(productId: i.productLocalId, quantity: i.quantity))
          .toList(),
      returnReason: returnReason,
      refundMethod: refundMethod,
    );
  }
}

extension ReturnRequestRowToDomain on ReturnRequestRow {
  /// `items` supplied separately — this row alone doesn't carry them
  /// (they live in the `ReturnItems` child table); the repository joins
  /// the two before calling this.
  ReturnRequest toDomain({required List<ReturnItem> items}) {
    return ReturnRequest(
      localId: localId,
      serverId: serverId,
      originalSaleLocalId: originalSaleLocalId,
      status: _statusFromColumn(status),
      returnReason: returnReason,
      refundAmount: refundAmount,
      refundMethod: refundMethod,
      inventoryRestored: inventoryRestored,
      items: items,
      createdAt: createdAt,
      updatedAt: updatedAt,
      completedAt: completedAt,
    );
  }
}

extension ReturnItemToCompanion on ReturnItem {
  ReturnItemsCompanion toDriftCompanion() {
    return ReturnItemsCompanion.insert(
      localId: localId,
      returnLocalId: returnLocalId,
      productLocalId: productLocalId,
      quantity: quantity,
    );
  }
}

extension ReturnItemRowToDomain on ReturnItemRow {
  ReturnItem toDomain() {
    return ReturnItem(
      localId: localId,
      returnLocalId: returnLocalId,
      productLocalId: productLocalId,
      quantity: quantity,
    );
  }
}
