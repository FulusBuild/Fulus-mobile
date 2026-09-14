import '../../data/local/database/database.dart';
import '../../data/remote/endpoints/suppliers_api.dart';
import '../../domain/entities/supplier.dart';
import '../../domain/repositories/supplier_repository.dart';
import '../sync_handler.dart';

class SupplierSyncHandler implements SyncHandler {
  SupplierSyncHandler({
    required SuppliersApi suppliersApi,
    required SupplierRepository supplierRepository,
  })  : _suppliersApi = suppliersApi,
        _supplierRepository = supplierRepository;

  final SuppliersApi _suppliersApi;
  final SupplierRepository _supplierRepository;

  @override
  Future<void> sync(SyncQueueItem item) async {
    if (item.operation != 'create') {
      throw StateError(
        'SupplierSyncHandler does not support operation "${item.operation}" '
        'yet — only "create" is implemented.',
      );
    }

    final supplier = await _supplierRepository.getSupplierById(item.entityLocalId);
    if (supplier == null) {
      throw StateError(
        'No local supplier found for ${item.entityLocalId} — the queue '
        'item outlived its own row.',
      );
    }

    final response = await _suppliersApi.createSupplier(
      SupplierCreateDto(
        name: supplier.name,
        phone: supplier.phone,
        email: supplier.email,
        address: supplier.address,
      ),
    );

    await _supplierRepository.markSynced(
      localId: supplier.localId,
      serverId: response.serverId!,
    );
  }
}
