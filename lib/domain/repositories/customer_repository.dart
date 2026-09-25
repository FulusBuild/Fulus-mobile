import '../entities/customer.dart';

/// Architecture Section 4's repository pattern, applied to Customers.
/// Unlike Location/Product, this is write-capable from mobile — a new
/// walk-in customer being added at checkout is a normal, common POS
/// flow, and Customers (unlike Products/Locations) has no reason to be
/// exclusively desktop-managed. Follows SaleRepository's exact shape:
/// local-write-first, enqueue for sync, never await the network in the
/// write path.
abstract class CustomerRepository {
  Future<Customer> createCustomer(CustomerDraft draft);

  /// Reactive by default — the customer picker at checkout (Volume 4)
  /// and a customer list/search screen both need this to update the
  /// instant a new customer is created or a synced change arrives.
  /// Excludes archived customers by default, matching every other read
  /// here. Pass [archivedOnly] to see only archived ones instead — used
  /// by the one screen that legitimately needs them, so an archived
  /// customer is reachable to restore.
  Stream<List<Customer>> watchCustomers({bool archivedOnly = false});

  Future<Customer?> getCustomerById(String localId);

  /// Feature (customer management): edits an existing customer's
  /// details — name/phone/email/address/notes/creditLimit. The mutation is
  /// local-first and enqueues an authoritative cloud update. [localId]
  /// must already exist; throws if it doesn't rather than silently creating
  /// a row.
  Future<Customer> updateCustomer(String localId, CustomerDraft draft);

  /// Soft delete: sets `deletedAt` and enqueues a customer update so the
  /// server's active flag converges with the local archive state.
  Future<void> archiveCustomer(String localId);

  /// The reverse of [archiveCustomer] — clears `deletedAt` and enqueues
  /// a customer update so the server can restore the customer.
  Future<void> restoreCustomer(String localId);

  /// Applies a canonical server snapshot without enqueueing an outbound
  /// sync task. If the server entity is already known locally, its local
  /// identity and local-only fields are preserved. If it is new to this
  /// device, a new local identity is allocated. This is an upsert, not a
  /// push, so a server change can never bounce back through SyncQueue.
  Future<void> reconcileServerState({
    required String serverId,
    required String name,
    String? phone,
    String? email,
    String? address,
    String? notes,
    required double outstandingBalance,
    String? duplicateWarning,
    required DateTime updatedAt,
    DateTime? deletedAt,
  });

  /// Applies a canonical delete without enqueueing an outbound task.
  /// Missing local rows are intentionally a no-op: there is nothing to
  /// reconcile on this device.
  Future<void> reconcileDeleted(String serverId);

  /// Reconciles a locally-created customer with the server's own
  /// identity once the sync engine's handler for this entity type
  /// successfully pushes it — same role as SaleRepository.markSynced.
  /// [duplicateWarning] is CustomerResponseDto's own field, passed
  /// through verbatim when the create response carried one.
  Future<void> markSynced({
    required String localId,
    required String serverId, String? operationId,
    String? duplicateWarning,
  });
}
