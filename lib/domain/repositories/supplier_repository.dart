import '../entities/supplier.dart';

/// Same shape as CategoryRepository/CustomerRepository.
abstract class SupplierRepository {
  Future<Supplier> createSupplier(SupplierDraft draft);

  Stream<List<Supplier>> watchSuppliers();

  Future<Supplier?> getSupplierById(String localId);

  /// Bug fix (suppliers gap-closure): edits an existing supplier's
  /// details — name/phone/email/address. Same local-only shape as
  /// `CustomerRepository.updateCustomer` and for the identical reason
  /// (`SupplierSyncHandler` only implements 'create' today) — no sync
  /// task enqueued. [localId] must already exist; throws if it
  /// doesn't, matching `updateCustomer`'s own contract.
  Future<Supplier> updateSupplier(String localId, SupplierDraft draft);

  Future<void> markSynced({required String localId, required String serverId});
}
