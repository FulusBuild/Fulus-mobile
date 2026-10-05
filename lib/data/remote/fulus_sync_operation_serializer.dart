/// Typed mapping between durable Fulus sync operation names and the
/// wire protocol expected by `fulus-api`.
///
/// The public sync queue still stores operation names as strings for durable
/// compatibility. Known operations are parsed into this closed enum before
/// transport serialization so protocol differences are owned here rather than
/// by the HTTP client itself. Unknown names retain the legacy envelope for
/// forward compatibility with newer server operations.
enum FulusSyncOperationType {
  saleCreate(
    'sale.create',
    action: 'sale_create',
    shape: FulusSyncOperationWireShape.flattenedAction,
    responseEntityIdKey: 'sale_id',
  ),
  customerCreate(
    'customer.create',
    action: 'customer_create',
    shape: FulusSyncOperationWireShape.flattenedAction,
    responseEntityIdKey: 'customer_id',
  ),
  customerRepayment(
    'customer.repayment',
    action: 'customer_repayment',
    shape: FulusSyncOperationWireShape.flattenedAction,
  ),
  expenseCreate(
    'expense.create',
    action: 'expense_create',
    shape: FulusSyncOperationWireShape.flattenedAction,
    responseEntityIdKey: 'id',
  ),
  returnCreate(
    'return.create',
    action: 'return_create',
    shape: FulusSyncOperationWireShape.flattenedAction,
    responseEntityIdKey: 'return_id',
  ),
  stockMovementCreate(
    'stock_movement.create',
    action: 'inventory_adjust',
    shape: FulusSyncOperationWireShape.flattenedAction,
    responseEntityIdKey: 'movement_id',
  ),
  stockAdjustmentCreate(
    'stock_adjustment.create',
    action: 'inventory_set',
    shape: FulusSyncOperationWireShape.flattenedAction,
    responseEntityIdKey: 'movement_id',
  ),
  locationCreate(
    'location.create',
    action: 'location_create',
    shape: FulusSyncOperationWireShape.flattenedAction,
    responseEntityIdKey: 'location_id',
  ),
  incomeCreate(
    'income.create',
    action: 'income_create',
    shape: FulusSyncOperationWireShape.flattenedAction,
    responseEntityIdKey: 'income_id',
  ),
  expenseCategoryCreate(
    'expense_category.create',
    action: 'expense_category_create',
    shape: FulusSyncOperationWireShape.payloadAction,
    responseEntityFromItem: true,
  ),
  cashDrawerShiftCreate(
    'cash_drawer_shift.create',
    action: 'cash_drawer_open',
    shape: FulusSyncOperationWireShape.flattenedAction,
    responseEntityIdKey: 'shift_id',
  ),
  cashDrawerShiftClose(
    'cash_drawer_shift.close',
    action: 'cash_drawer_close',
    shape: FulusSyncOperationWireShape.flattenedAction,
    responseEntityIdKey: 'shift_id',
  ),
  employeeCreate(
    'employee.create',
    action: 'employee_create',
    shape: FulusSyncOperationWireShape.payloadAction,
  ),
  employeeUpdate(
    'employee.update',
    action: 'employee_update',
    shape: FulusSyncOperationWireShape.payloadAction,
  ),
  customerUpdate(
    'customer.update',
    action: 'customer_update',
    shape: FulusSyncOperationWireShape.payloadAction,
  ),
  expenseUpdate(
    'expense.update',
    action: 'expense_update',
    shape: FulusSyncOperationWireShape.payloadAction,
  ),
  productCreate(
    'product.create',
    shape: FulusSyncOperationWireShape.catalog,
    catalogEntity: 'products',
    catalogOperation: FulusSyncCatalogOperation.upsert,
    responseEntityFromItem: true,
  ),
  productUpdate(
    'product.update',
    shape: FulusSyncOperationWireShape.catalog,
    catalogEntity: 'products',
    catalogOperation: FulusSyncCatalogOperation.upsert,
    responseEntityFromItem: true,
  ),
  productDelete(
    'product.delete',
    shape: FulusSyncOperationWireShape.catalog,
    catalogEntity: 'products',
    catalogOperation: FulusSyncCatalogOperation.delete,
    responseEntityFromItem: true,
  ),
  categoryCreate(
    'category.create',
    shape: FulusSyncOperationWireShape.catalog,
    catalogEntity: 'categories',
    catalogOperation: FulusSyncCatalogOperation.upsert,
    responseEntityFromItem: true,
  ),
  categoryUpdate(
    'category.update',
    shape: FulusSyncOperationWireShape.catalog,
    catalogEntity: 'categories',
    catalogOperation: FulusSyncCatalogOperation.upsert,
    responseEntityFromItem: true,
  ),
  categoryDelete(
    'category.delete',
    shape: FulusSyncOperationWireShape.catalog,
    catalogEntity: 'categories',
    catalogOperation: FulusSyncCatalogOperation.delete,
    responseEntityFromItem: true,
  ),
  supplierCreate(
    'supplier.create',
    shape: FulusSyncOperationWireShape.catalog,
    catalogEntity: 'suppliers',
    catalogOperation: FulusSyncCatalogOperation.upsert,
    responseEntityFromItem: true,
  ),
  supplierUpdate(
    'supplier.update',
    shape: FulusSyncOperationWireShape.catalog,
    catalogEntity: 'suppliers',
    catalogOperation: FulusSyncCatalogOperation.upsert,
    responseEntityFromItem: true,
  ),
  supplierDelete(
    'supplier.delete',
    shape: FulusSyncOperationWireShape.catalog,
    catalogEntity: 'suppliers',
    catalogOperation: FulusSyncCatalogOperation.delete,
    responseEntityFromItem: true,
  );

  const FulusSyncOperationType(
    this.value, {
    this.action,
    required this.shape,
    this.catalogEntity,
    this.catalogOperation,
    this.responseEntityIdKey,
    this.responseEntityFromItem = false,
  });

  final String value;
  final String? action;
  final FulusSyncOperationWireShape shape;
  final String? catalogEntity;
  final FulusSyncCatalogOperation? catalogOperation;
  final String? responseEntityIdKey;
  final bool responseEntityFromItem;

  static FulusSyncOperationType? tryParse(String value) {
    for (final type in values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

enum FulusSyncOperationWireShape {
  flattenedAction,
  payloadAction,
  catalog,
}

enum FulusSyncCatalogOperation {
  upsert,
  delete,
}

class FulusSyncOperationSerializer {
  const FulusSyncOperationSerializer();

  Map<String, dynamic> serialize({
    required String businessId,
    required String operationType,
    required String operationId,
    String? clientReference,
    Object? payload,
  }) {
    final rawPayload = payload is Map
        ? Map<String, dynamic>.from(payload)
        : <String, dynamic>{};
    final body = <String, dynamic>{
      'business_id': businessId,
      'operation_type': operationType,
      'operation_id': operationId,
      if (clientReference != null) 'client_reference': clientReference,
      'payload': payload,
    };

    final type = FulusSyncOperationType.tryParse(operationType);
    if (type == null) return body;

    switch (type.shape) {
      case FulusSyncOperationWireShape.flattenedAction:
        body
          ..remove('operation_type')
          ..remove('payload')
          ..addAll(rawPayload)
          ..['action'] = type.action;
      case FulusSyncOperationWireShape.payloadAction:
        body
          ..remove('operation_type')
          ..remove('payload')
          ..['action'] = type.action
          ..['payload'] = rawPayload;
      case FulusSyncOperationWireShape.catalog:
        final catalogEntity = type.catalogEntity;
        final catalogOperation = type.catalogOperation;
        if (catalogEntity == null || catalogOperation == null) {
          throw StateError('Invalid catalog operation definition: $operationType');
        }
        body
          ..remove('operation_type')
          ..remove('payload')
          ..['action'] = catalogOperation == FulusSyncCatalogOperation.delete
              ? 'catalog_delete'
              : 'catalog_upsert'
          ..['entity'] = catalogEntity;
        if (catalogOperation == FulusSyncCatalogOperation.delete) {
          body['id'] = rawPayload['server_id'];
        } else {
          body['item'] = rawPayload;
          if (operationType.endsWith('.update')) {
            body['id'] = rawPayload['server_id'];
          }
        }
    }

    return body;
  }

  Map<String, dynamic> normalizeResponse(
    Map<String, dynamic> result, {
    required String operationType,
  }) {
    final type = FulusSyncOperationType.tryParse(operationType);
    if (type == null || (type.responseEntityIdKey == null && !type.responseEntityFromItem)) {
      return result;
    }

    final rawData = result['data'];
    if (rawData is! Map) return result;
    final data = Map<String, dynamic>.from(rawData);

    if (type.responseEntityFromItem) {
      final rawItem = data['item'];
      if (rawItem is! Map) return result;
      final item = Map<String, dynamic>.from(rawItem);
      return {
        ...Map<String, dynamic>.from(result),
        'data': {...data, 'entity_id': item['id'], 'entity': item},
      };
    }

    final entityIdKey = type.responseEntityIdKey!;
    final entityId = data[entityIdKey];
    if (entityId != null) {
      return {
        ...Map<String, dynamic>.from(result),
        'data': {...data, 'entity_id': entityId},
      };
    }
    return result;
  }
}
