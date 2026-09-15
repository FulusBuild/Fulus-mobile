import 'package:drift/drift.dart';

import '../../data/local/database/database.dart';
import '../../data/local/database/tables.dart';
import '../../data/local/secure_storage/secure_storage.dart';
import '../../data/remote/fulus_connection_state.dart';
import '../../data/remote/fulus_sync_api.dart';
import '../sync_handler.dart';

/// Pushes customer repayment ledger entries to the server.
class CustomerLedgerSyncHandler implements SyncHandler {
  CustomerLedgerSyncHandler({
    required AppDatabase db,
    required FulusSyncApi fulusSyncApi,
    required FulusConnectionState fulusConnectionState,
    required SecureStorage secureStorage,
  })  : _db = db,
        _fulusSyncApi = fulusSyncApi,
        _fulusConnectionState = fulusConnectionState,
        _secureStorage = secureStorage;

  final AppDatabase _db;
  final FulusSyncApi _fulusSyncApi;
  final FulusConnectionState _fulusConnectionState;
  final SecureStorage _secureStorage;

  @override
  Future<void> sync(SyncQueueItem item) async {
    if (item.operation != 'repayment') {
      throw StateError('CustomerLedgerSyncHandler does not support operation "${item.operation}".');
    }
    final ledger = await (_db.select(_db.customerLedgerEntries)
          ..where((e) => e.localId.equals(item.entityLocalId)))
        .getSingleOrNull();
    if (ledger == null) throw StateError('No local customer ledger entry found for ${item.entityLocalId}.');
    if (ledger.serverId != null && ledger.serverId!.isNotEmpty) {
      await _markSettled(ledger.localId, ledger.serverId!);
      return;
    }
    final businessId = _fulusConnectionState.selectedBusinessId;
    if (businessId == null || businessId.isEmpty) throw StateError('No active Fulus Cloud business is selected.');
    final customer = await (_db.select(_db.customers)
          ..where((c) => c.localId.equals(ledger.customerLocalId)))
        .getSingleOrNull();
    if (customer == null) throw StateError('No local customer found for ${ledger.customerLocalId}.');
    final customerId = customer.serverId;
    if (customerId == null || customerId.isEmpty) {
      throw StateError('Customer ${ledger.customerLocalId} has not synced to Fulus Cloud yet.');
    }
    final deviceClientId = await _secureStorage.ensureDeviceClientId(item.id);
    final result = await _fulusSyncApi.submitOperation(
      businessId: businessId,
      operationType: 'customer.repayment',
      operationId: item.id,
      deviceClientId: deviceClientId,
      payload: {
        'business_id': businessId,
        'customer_id': customerId,
        'amount': ledger.amount,
        'operation_id': item.id,
        if (ledger.paymentMethod != null) 'payment_method': ledger.paymentMethod,
        if (ledger.note != null) 'note': ledger.note,
      },
    );
    final data = result['data'];
    if (data is! Map) throw StateError('Customer repayment sync returned no ledger result.');
    final ledgerId = data['ledger_id']?.toString();
    if (ledgerId == null || ledgerId.isEmpty) throw StateError('Customer repayment sync returned no ledger id.');
    await _markSettled(ledger.localId, ledgerId);
  }

  Future<void> _markSettled(String localId, String serverId) async {
    await (_db.update(_db.customerLedgerEntries)..where((e) => e.localId.equals(localId))).write(
      CustomerLedgerEntriesCompanion(
        serverId: Value(serverId),
        syncStatus: const Value(SyncStatus.settled),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
