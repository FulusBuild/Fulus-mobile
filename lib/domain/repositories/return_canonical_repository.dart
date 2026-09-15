import '../entities/return_canonical_state.dart';

abstract class ReturnCanonicalRepository {
  Future<void> reconcileServerState(ReturnCanonicalState state);
  Future<void> reconcileDeleted(String serverId);
}
