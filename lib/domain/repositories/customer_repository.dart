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
  Stream<List<Customer>> watchCustomers();

  Future<Customer?> getCustomerById(String localId);

  /// Reconciles a locally-created customer with the server's own
  /// identity once the (not yet built) sync engine handler for this
  /// entity type successfully pushes it — same role as
  /// SaleRepository.markSynced.
  Future<void> markSynced({required String localId, required String serverId});
}
