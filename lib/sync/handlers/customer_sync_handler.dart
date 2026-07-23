import '../../data/local/database/database.dart';
import '../../data/remote/endpoints/customers_api.dart';
import '../../domain/repositories/customer_repository.dart';
import '../sync_handler.dart';

class CustomerSyncHandler implements SyncHandler {
  CustomerSyncHandler({
    required CustomersApi customersApi,
    required CustomerRepository customerRepository,
  })  : _customersApi = customersApi,
        _customerRepository = customerRepository;

  final CustomersApi _customersApi;
  final CustomerRepository _customerRepository;

  @override
  Future<void> sync(SyncQueueItem item) async {
    if (item.operation != 'create') {
      // No caller in this codebase enqueues 'update'/'delete' for
      // 'customer' today — SyncTask.createCustomer is the only factory
      // that exists. Kept as an explicit, honest failure rather than
      // silently doing nothing if this is ever somehow reached.
      throw StateError(
        'CustomerSyncHandler does not support operation "${item.operation}" '
        'yet — only "create" is implemented.',
      );
    }

    final customer = await _customerRepository.getCustomerById(item.entityLocalId);
    if (customer == null) {
      throw StateError(
        'No local customer found for ${item.entityLocalId} — the queue '
        'item outlived its own row.',
      );
    }

    // Unlike SaleSyncHandler, there is no product/customer-serverId gap
    // to resolve here — a Customer has no foreign keys of its own into
    // anything else that would need its own prior sync.
    final response = await _customersApi.createCustomer(
      customer.toCreateDto(clientReference: customer.localId),
    );

    await _customerRepository.markSynced(
      localId: customer.localId,
      serverId: response.serverId!,
    );
  }
}
