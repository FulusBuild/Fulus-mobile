import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/core/money/money.dart';

import 'package:fulus_mobile/data/remote/fulus_customer_ledger_canonical_reconciler.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';
import 'package:fulus_mobile/domain/entities/customer_ledger_entry.dart';
import 'package:fulus_mobile/domain/repositories/customer_credit_repository.dart';

class _FakeCustomerCreditRepository implements CustomerCreditRepository {
  CustomerLedgerEntryType? entryType;
  String? serverId;
  Money? amount;
  String? operationId;

  @override
  Future<void> reconcileServerState({
    required String serverId,
    required String customerServerId,
    String? saleServerId,
    required CustomerLedgerEntryType entryType,
    required Money amount,
    String? paymentMethod,
    String? note,
    required DateTime createdAt,
    required DateTime updatedAt,
    String? operationId,
  }) async {
    this.serverId = serverId;
    this.entryType = entryType;
    this.amount = amount;
    this.operationId = operationId;
  }

  @override
  Future<CustomerLedgerEntry> recordCreditSale({
    required String customerLocalId,
    required Money amount,
    required String saleLocalId,
  }) => throw UnimplementedError();

  @override
  Future<({CustomerLedgerEntry entry, Money newBalance, Money excessAmount})>
      recordRepayment({
    required String customerLocalId,
    required Money amount,
    String? paymentMethod,
    String? note,
    String? saleLocalId,
  }) => throw UnimplementedError();

  @override
  Future<CustomerLedgerEntry> recordRefundAdjustment({
    required String customerLocalId,
    required Money amount,
    required String saleLocalId,
  }) => throw UnimplementedError();

  @override
  Stream<List<CustomerLedgerEntry>> watchLedger(String customerLocalId) =>
      throw UnimplementedError();

  @override
  Future<List<CustomerLedgerEntry>> getRepaymentsForPeriod({
    required DateTime start,
    required DateTime end,
  }) => throw UnimplementedError();

  @override
  Future<void> reconcileDeleted(String serverId) async {}
}

void main() {
  test('normalizes cloud credit_reversal into local refundAdjustment', () async {
    final repository = _FakeCustomerCreditRepository();
    final reconciler =
        FulusCustomerLedgerCanonicalReconciler(repository: repository);

    await reconciler.apply(
      const FulusCanonicalEntityResponse(
        data: {
          'entity_type': 'customer_ledger',
          'entity_id': 'ledger-1',
          'operation': 'upsert',
          'row': {
            'id': 'ledger-1',
            'customer_id': 'customer-1',
            'sale_id': 'sale-1',
            'entry_type': 'credit_reversal',
            'amount': '25.00',
            'payment_method': null,
            'note': 'Return credit reversal',
            'created_at': '2026-09-23T20:00:00Z',
          },
        },
      ),
    );

    expect(repository.serverId, 'ledger-1');
    expect(repository.entryType, CustomerLedgerEntryType.refundAdjustment);
    expect(repository.amount, moneyFromMajor(25));
  });

  test('uses created_at when canonical customer ledger has no updated_at', () async {
    final repository = _FakeCustomerCreditRepository();
    final reconciler =
        FulusCustomerLedgerCanonicalReconciler(repository: repository);

    await reconciler.apply(
      const FulusCanonicalEntityResponse(
        data: {
          'entity_type': 'customer_ledger',
          'entity_id': 'ledger-2',
          'operation': 'upsert',
          'row': {
            'id': 'ledger-2',
            'customer_id': 'customer-1',
            'entry_type': 'repayment',
            'amount': '10.00',
            'operation_id': 'repayment-operation-1',
            'created_at': '2026-09-24T08:00:00Z',
          },
        },
      ),
    );

    expect(repository.serverId, 'ledger-2');
    expect(repository.entryType, CustomerLedgerEntryType.repayment);
    expect(repository.amount, moneyFromMajor(10));
    expect(repository.operationId, 'repayment-operation-1');
  });
}
