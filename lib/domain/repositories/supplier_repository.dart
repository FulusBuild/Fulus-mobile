import '../entities/supplier.dart';

/// Same shape as CategoryRepository/CustomerRepository.
abstract class SupplierRepository {
  Future<Supplier> createSupplier(SupplierDraft draft);

  Stream<List<Supplier>> watchSuppliers();

  Future<Supplier?> getSupplierById(String localId);

  Future<Supplier> updateSupplier(String localId, SupplierDraft draft);

  /// Applies a canonical server snapshot without enqueueing an outbound
  /// sync task. Server identity is matched before allocating a local
  /// identity, preventing a second local row when another device creates
  /// the supplier.
  Future<void> reconcileServerState({
    required String serverId,
    required String name,
    String? phone,
    String? email,
    String? address,
    required DateTime updatedAt,
    DateTime? deletedAt,
  });

  /// Applies a canonical delete without enqueueing an outbound task.
  Future<void> reconcileDeleted(String serverId);

  Future<void> markSynced({required String localId, required String serverId});
}
