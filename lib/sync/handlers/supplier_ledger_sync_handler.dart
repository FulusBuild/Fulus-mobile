import '../../core/money/money.dart';
import '../../data/local/database/database.dart';
import '../../data/remote/fulus_connection_state.dart';
import '../../data/remote/fulus_sync_api.dart';
import '../../data/repositories/supplier_credit_repository_impl.dart';
import '../../data/local/secure_storage/secure_storage.dart';
import '../../domain/entities/supplier_ledger_entry.dart';
import '../sync_handler.dart';

/// Sends append-only supplier payable entries to the canonical cloud ledger.
class SupplierLedgerSyncHandler implements SyncHandler {
  SupplierLedgerSyncHandler({
    required AppDatabase db,
    required SupplierCreditRepositoryImpl repository,
    required FulusSyncApi fulusSyncApi,
    required FulusConnectionState fulusConnectionState,
    required SecureStorage secureStorage,
  }) : _db = db,
       _repository = repository,
       _fulusSyncApi = fulusSyncApi,
       _fulusConnectionState = fulusConnectionState,
       _secureStorage = secureStorage;

  final AppDatabase _db;
  final SupplierCreditRepositoryImpl _repository;
  final FulusSyncApi _fulusSyncApi;
  final FulusConnectionState _fulusConnectionState;
  final SecureStorage _secureStorage;

  @override
  Future<void> sync(SyncQueueItem item) async {
    if (item.operation != 'create') {
      throw StateError(
        'SupplierLedgerSyncHandler does not support ${item.operation}.',
      );
    }
    final entry =
        await (_db.select(_db.supplierLedgerEntries)
              ..where((row) => row.localId.equals(item.entityLocalId)))
            .getSingleOrNull();
    if (entry == null) {
      throw StateError(
        'No local supplier ledger entry found for ${item.entityLocalId}.',
      );
    }
    final businessId = _fulusConnectionState.selectedBusinessId;
    if (businessId == null || businessId.isEmpty) {
      throw StateError('No active Fulus Cloud business is selected.');
    }
    final supplier =
        await (_db.select(_db.suppliers)
              ..where((row) => row.localId.equals(entry.supplierLocalId)))
            .getSingleOrNull();
    if (supplier?.serverId == null || supplier!.serverId!.isEmpty) {
      throw StateError('Supplier must sync before its payable ledger entries.');
    }
    final locationId = entry.locationLocalId;
    if (locationId == null) {
      throw StateError(
        'Supplier ledger entry has no location; it cannot be synced safely.',
      );
    }
    final location = await (_db.select(
      _db.locations,
    )..where((row) => row.localId.equals(locationId))).getSingleOrNull();
    if (location?.serverId == null || location!.serverId!.isEmpty) {
      throw StateError(
        'Location must sync before its supplier ledger entries.',
      );
    }
    final stockMovement = entry.stockMovementLocalId == null
        ? null
        : await (_db.select(_db.stockMovements)..where(
                (row) => row.localId.equals(entry.stockMovementLocalId!),
              ))
              .getSingleOrNull();
    if (entry.stockMovementLocalId != null && stockMovement?.serverId == null) {
      throw StateError(
        'Stock movement must sync before its supplier payable entry.',
      );
    }
    final shift = entry.cashDrawerShiftLocalId == null
        ? null
        : await (_db.select(_db.cashDrawerShifts)..where(
                (row) => row.localId.equals(entry.cashDrawerShiftLocalId!),
              ))
              .getSingleOrNull();
    if (entry.cashDrawerShiftLocalId != null && shift?.serverId == null) {
      throw StateError(
        'Cash drawer shift must sync before its supplier payment.',
      );
    }

    final deviceClientId =
        _fulusConnectionState.registeredDevice?.deviceClientId ??
        await _secureStorage.ensureDeviceClientId(item.id);
    final result = await _fulusSyncApi.submitOperation(
      businessId: businessId,
      operationType: 'supplier_ledger.create',
      operationId: item.id,
      deviceClientId: deviceClientId,
      payload: {
        'business_id': businessId,
        'supplier_id': supplier.serverId,
        'location_id': location.serverId,
        'entry_type': switch (entry.entryType) {
          'stockPurchaseOnCredit' => 'stock_purchase_on_credit',
          'paymentMade' => 'payment_made',
          _ => throw StateError(
            'Unknown supplier ledger entry type ${entry.entryType}.',
          ),
        },
        'amount': moneyToWire(entry.amount),
        'operation_id': item.id,
        'created_at': entry.createdAt.toUtc().toIso8601String(),
        if (entry.paymentMethod != null) 'payment_method': entry.paymentMethod,
        if (entry.note != null) 'note': entry.note,
        if (stockMovement?.serverId != null)
          'stock_movement_id': stockMovement!.serverId,
        if (shift?.serverId != null) 'cash_drawer_shift_id': shift!.serverId,
      },
    );
    final data = result['data'];
    if (data is! Map)
      throw StateError('Supplier ledger sync returned no canonical entry.');
    final ledgerId = data['ledger_id']?.toString();
    if (ledgerId == null || ledgerId.isEmpty) {
      throw StateError('Supplier ledger sync returned no ledger id.');
    }
    await _repository.reconcileServerEntry(
      serverId: ledgerId,
      operationId: item.id,
      supplierServerId: supplier.serverId!,
      locationServerId: location.serverId!,
      stockMovementServerId: stockMovement?.serverId,
      cashDrawerShiftServerId: shift?.serverId,
      entryType: entry.entryType == 'stockPurchaseOnCredit'
          ? SupplierLedgerEntryType.stockPurchaseOnCredit
          : SupplierLedgerEntryType.paymentMade,
      amount: entry.amount,
      balanceAfter: moneyFromWire(data['new_balance']),
      paymentMethod: entry.paymentMethod,
      note: entry.note,
      createdAt: entry.createdAt,
    );
  }
}
