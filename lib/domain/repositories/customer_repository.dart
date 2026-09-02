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
  /// details — name/phone/email/address/notes/creditLimit. Local-only,
  /// same as [archiveCustomer]/[restoreCustomer] and for the identical
  /// reason (CustomerSyncHandler only implements 'create' today, see
  /// that class's own doc comment) — no sync task enqueued. [localId]
  /// must already exist; throws if it doesn't rather than silently
  /// creating a row, since a caller editing a customer always has one
  /// in hand already (the profile screen it's editing from).
  Future<Customer> updateCustomer(String localId, CustomerDraft draft);

  /// Soft delete: sets `deletedAt`, same convention as every other
  /// SyncableColumns table — [watchCustomers] already filters on it.
  /// Local-only, deliberately: [CustomerSyncHandler] only implements
  /// the 'create' operation today (see that class's own comment) and
  /// would throw on anything else, so this doesn't enqueue a sync task.
  /// The archive is real on this device; it just doesn't reach the
  /// backend or other devices yet.
  Future<void> archiveCustomer(String localId);

  /// The reverse of [archiveCustomer] — clears `deletedAt`. Same
  /// local-only constraint applies.
  Future<void> restoreCustomer(String localId);

  /// Reconciles a locally-created customer with the server's own
  /// identity once the sync engine's handler for this entity type
  /// successfully pushes it — same role as SaleRepository.markSynced.
  /// [duplicateWarning] is CustomerResponseDto's own field, passed
  /// through verbatim when the create response carried one — see that
  /// DTO's doc comment for exactly how far this gets taken (stored,
  /// not yet surfaced to any UI).
  Future<void> markSynced({
    required String localId,
    required String serverId,
    String? duplicateWarning,
  });
}
