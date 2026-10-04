/// Internal runtime contract used by [SyncService].
///
/// Application code must depend on SyncService, not this adapter. The contract
/// deliberately contains synchronization operations rather than lifecycle
/// implementation details such as connectivity subscriptions, timers, leases,
/// cursors, or handler dispatch.
abstract interface class SyncRuntime {
  Future<void> start();
  void stop();
  Future<void> request();
  Future<void> waitForIdle();
  Future<void> refreshAfterContextChange();
  Future<void> reconcileAfterRestore();
  Future<void> reconcileForReadiness();
  Future<void> onLocalMutationCommitted();
  void recoverReadiness();
  void beginRestoreReconciliation();
  void cancelRestoreReconciliation();
  void dispose();
}
