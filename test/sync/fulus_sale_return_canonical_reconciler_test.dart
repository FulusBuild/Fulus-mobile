import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fulus_mobile/data/remote/fulus_return_canonical_reconciler.dart';
import 'package:fulus_mobile/data/remote/fulus_sale_canonical_reconciler.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';
import 'package:fulus_mobile/domain/entities/return_canonical_state.dart';
import 'package:fulus_mobile/domain/entities/sale_canonical_state.dart';
import 'package:fulus_mobile/domain/repositories/return_canonical_repository.dart';
import 'package:fulus_mobile/domain/repositories/sale_canonical_repository.dart';

class _MockSaleCanonicalRepository extends Mock implements SaleCanonicalRepository {}
class _MockReturnCanonicalRepository extends Mock implements ReturnCanonicalRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(SaleCanonicalState(
      serverId: 'fallback',
      clientReference: 'fallback',
      invoiceNumber: null,
      customerServerId: null,
      locationServerId: 'fallback',
      cashierUserId: null,
      saleDate: DateTime(2026),
      subtotal: 0,
      discount: 0,
      tax: 0,
      total: 0,
      amountPaid: 0,
      paymentMethod: 'cash',
      notes: null,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      deletedAt: null,
      items: const [],
      payments: const [],
    ));
    registerFallbackValue(ReturnCanonicalState(
      serverId: 'fallback',
      originalSaleServerId: 'fallback',
      status: 'completed',
      returnReason: 'fallback',
      refundAmount: 0,
      refundMethod: 'cash',
      inventoryRestored: false,
      isVoid: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      completedAt: null,
      items: const [],
    ));
  });

  test('maps canonical sale aggregate and rejects delete as outbound work', () async {
    final repository = _MockSaleCanonicalRepository();
    when(() => repository.reconcileServerState(any())).thenAnswer((_) async {});
    when(() => repository.reconcileDeleted(any())).thenAnswer((_) async {});
    final reconciler = FulusSaleCanonicalReconciler(repository: repository);
    final response = FulusCanonicalEntityResponse.fromJson({
      'data': {
        'entity_type': 'sale',
        'entity_id': 'sale-1',
        'operation': 'upsert',
        'sale': {
          'id': 'sale-1',
          'client_reference': 'client-1',
          'invoice_number': 'INV-1',
          'customer_id': null,
          'location_id': 'location-1',
          'cashier_user_id': null,
          'sale_date': '2026-09-15T10:00:00Z',
          'subtotal': 1000,
          'discount': 0,
          'tax': 0,
          'total': 1000,
          'amount_paid': 1000,
          'payment_method': 'cash',
          'notes': null,
          'created_at': '2026-09-15T10:00:00Z',
          'updated_at': '2026-09-15T10:01:00Z',
          'deleted_at': null,
        },
        'sale_items': [
          {
            'id': 'item-1',
            'product_id': 'product-1',
            'quantity': 2,
            'unit_price': 500,
            'cost_price_at_sale': 300,
            'line_total': 1000,
          },
        ],
        'sale_payments': [
          {'id': 'payment-1', 'method': 'cash', 'amount': 1000, 'recorded_at': '2026-09-15T10:00:00Z'},
        ],
      },
    });

    await reconciler.apply(response);

    final captured = verify(() => repository.reconcileServerState(captureAny())).captured.single as SaleCanonicalState;
    expect(captured.serverId, 'sale-1');
    expect(captured.items.single.productServerId, 'product-1');
    expect(captured.payments.single.amount, 1000);
  });

  test('maps canonical return aggregate', () async {
    final repository = _MockReturnCanonicalRepository();
    when(() => repository.reconcileServerState(any())).thenAnswer((_) async {});
    when(() => repository.reconcileDeleted(any())).thenAnswer((_) async {});
    final reconciler = FulusReturnCanonicalReconciler(repository: repository);
    final response = FulusCanonicalEntityResponse.fromJson({
      'data': {
        'entity_type': 'return',
        'entity_id': 'return-1',
        'operation': 'upsert',
        'row': {
          'id': 'return-1',
          'original_sale_id': 'sale-1',
          'status': 'completed',
          'return_reason': 'Damaged',
          'refund_amount': 500,
          'refund_method': 'cash',
          'inventory_restored': true,
          'is_void': false,
          'created_at': '2026-09-15T11:00:00Z',
          'updated_at': '2026-09-15T11:01:00Z',
          'completed_at': '2026-09-15T11:01:00Z',
        },
        'return_items': [
          {'id': 'return-item-1', 'product_id': 'product-1', 'quantity': 1},
        ],
      },
    });

    await reconciler.apply(response);

    final captured = verify(() => repository.reconcileServerState(captureAny())).captured.single as ReturnCanonicalState;
    expect(captured.serverId, 'return-1');
    expect(captured.originalSaleServerId, 'sale-1');
    expect(captured.items.single.quantity, 1);
  });

  test('routes sale and return deletes without outbound writes', () async {
    final saleRepository = _MockSaleCanonicalRepository();
    final returnRepository = _MockReturnCanonicalRepository();
    when(() => saleRepository.reconcileDeleted(any())).thenAnswer((_) async {});
    when(() => returnRepository.reconcileDeleted(any())).thenAnswer((_) async {});
    final saleReconciler = FulusSaleCanonicalReconciler(repository: saleRepository);
    final returnReconciler = FulusReturnCanonicalReconciler(repository: returnRepository);

    await saleReconciler.apply(FulusCanonicalEntityResponse.fromJson({'data': {'entity_type': 'sale', 'entity_id': 'sale-2', 'operation': 'delete'}}));
    await returnReconciler.apply(FulusCanonicalEntityResponse.fromJson({'data': {'entity_type': 'return', 'entity_id': 'return-2', 'operation': 'delete'}}));

    verify(() => saleRepository.reconcileDeleted('sale-2')).called(1);
    verify(() => returnRepository.reconcileDeleted('return-2')).called(1);
  });
}
