import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_operation_serializer.dart';

void main() {
  const serializer = FulusSyncOperationSerializer();

  group('operation type definitions', () {
    test('all defined operations round-trip through their wire name', () {
      for (final type in FulusSyncOperationType.values) {
        expect(FulusSyncOperationType.tryParse(type.value), same(type));
      }
    });
  });

  group('serialize', () {
    test('transaction operation flattens payload and selects server action', () {
      final body = serializer.serialize(
        businessId: 'business-1',
        operationType: 'sale.create',
        operationId: 'op-1',
        clientReference: 'sale-ref',
        payload: {'location_id': 'location-1', 'amount_paid': 30000},
      );
      expect(body, {
        'business_id': 'business-1',
        'operation_id': 'op-1',
        'client_reference': 'sale-ref',
        'location_id': 'location-1',
        'amount_paid': 30000,
        'action': 'sale_create',
      });
    });

    test('command operation keeps payload nested', () {
      final body = serializer.serialize(
        businessId: 'business-1',
        operationType: 'employee.update',
        operationId: 'op-2',
        payload: {'server_id': 'employee-1', 'full_name': 'Ada'},
      );
      expect(body, {
        'business_id': 'business-1',
        'operation_id': 'op-2',
        'action': 'employee_update',
        'payload': {'server_id': 'employee-1', 'full_name': 'Ada'},
      });
    });

    test('expense category create preserves flattened command wire shape', () {
      final body = serializer.serialize(
        businessId: 'business-1',
        operationType: 'expense_category.create',
        operationId: 'op-expense-category',
        payload: {'name': 'Fuel'},
      );
      expect(body, {
        'business_id': 'business-1',
        'operation_id': 'op-expense-category',
        'name': 'Fuel',
        'action': 'expense_category_create',
      });
    });

    test('catalog upsert uses typed entity metadata and update id', () {
      final body = serializer.serialize(
        businessId: 'business-1',
        operationType: 'product.update',
        operationId: 'op-3',
        payload: {'server_id': 'product-1', 'name': 'Rice'},
      );
      expect(body, {
        'business_id': 'business-1',
        'operation_id': 'op-3',
        'action': 'catalog_upsert',
        'entity': 'products',
        'item': {'server_id': 'product-1', 'name': 'Rice'},
        'id': 'product-1',
      });
    });

    test('catalog delete sends the server id without an item payload', () {
      final body = serializer.serialize(
        businessId: 'business-1',
        operationType: 'supplier.delete',
        operationId: 'op-4',
        payload: {'server_id': 'supplier-1', 'name': 'Vendor'},
      );
      expect(body, {
        'business_id': 'business-1',
        'operation_id': 'op-4',
        'action': 'catalog_delete',
        'entity': 'suppliers',
        'id': 'supplier-1',
      });
    });

    test('unknown operation preserves the legacy envelope', () {
      final body = serializer.serialize(
        businessId: 'business-1',
        operationType: 'future.operation',
        operationId: 'op-5',
        payload: {'value': true},
      );
      expect(body, {
        'business_id': 'business-1',
        'operation_type': 'future.operation',
        'operation_id': 'op-5',
        'payload': {'value': true},
      });
    });
  });

  group('normalizeResponse', () {
    test('maps transaction response ids to the common entity id', () {
      final result = {'data': {'sale_id': 'sale-1', 'status': 'applied'}};
      final normalized = serializer.normalizeResponse(result, operationType: 'sale.create');
      expect(normalized['data'], {
        'sale_id': 'sale-1',
        'status': 'applied',
        'entity_id': 'sale-1',
      });
    });

    test('maps catalog item responses to entity id and entity', () {
      final result = {
        'data': {'item': {'id': 'product-1', 'name': 'Rice'}},
      };
      final normalized = serializer.normalizeResponse(result, operationType: 'product.update');
      expect(normalized['data'], {
        'item': {'id': 'product-1', 'name': 'Rice'},
        'entity_id': 'product-1',
        'entity': {'id': 'product-1', 'name': 'Rice'},
      });
    });

    test('maps expense category responses without treating them as catalog writes', () {
      final result = {
        'data': {'item': {'id': 'expense-category-1', 'name': 'Fuel'}},
      };
      final normalized = serializer.normalizeResponse(result, operationType: 'expense_category.create');
      expect(normalized['data'], {
        'item': {'id': 'expense-category-1', 'name': 'Fuel'},
        'entity_id': 'expense-category-1',
        'entity': {'id': 'expense-category-1', 'name': 'Fuel'},
      });
    });

    test('leaves responses without a known entity id unchanged', () {
      final result = {'data': {'status': 'already_applied'}};
      expect(
        serializer.normalizeResponse(result, operationType: 'employee.update'),
        same(result),
      );
    });
  });
}