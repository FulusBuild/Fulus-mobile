import '../entities/sale_canonical_state.dart';

abstract class SaleCanonicalRepository {
  Future<void> reconcileServerState(SaleCanonicalState state);
  Future<void> reconcileDeleted(String serverId);
}
