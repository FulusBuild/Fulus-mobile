import '../entities/supplier.dart';

/// Same shape as CategoryRepository/CustomerRepository.
abstract class SupplierRepository {
  Future<Supplier> createSupplier(SupplierDraft draft);

  Stream<List<Supplier>> watchSuppliers();

  Future<Supplier?> getSupplierById(String localId);

  Future<void> markSynced({required String localId, required String serverId});
}
