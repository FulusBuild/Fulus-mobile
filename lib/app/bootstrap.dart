  final syncBootstrapCoordinator = CloudSyncBootstrapCoordinator(database);
  late final CloudSyncRecovery syncRecovery;
  late final SyncTriggers syncTriggers;

  syncRecovery = CloudSyncRecovery(
    db: database,
    restoreApi: cloudRestoreApi,
    bootstrapCoordinator: syncBootstrapCoordinator,
    onStarted: () async {
      final businessId = fulusConnectionState.selectedBusinessId;
      if (businessId != null) {
        fulusConnectionState.clearSyncReady();
        await syncStatusNotifier.markRecoveryStarted(businessId);
      }
    },
    onCompleted: (boundary) async {
      final businessId = fulusConnectionState.selectedBusinessId;
      if (businessId != null) {
        // The restore transaction has committed at this point. Persist its
        // authoritative sync boundary before the post-bootstrap delta pull;
        // otherwise pull would reuse the stale pre-recovery cursor and can
        // immediately trigger another SYNC_CURSOR_TOO_OLD recovery.
        await syncCoordinator.setCursor(businessId, boundary);
        await syncStatusNotifier.markRecoveryCompleted(businessId, boundary);
        fulusConnectionState.clearSyncError();
      }
    },
    onFailed: (error) async {
      final businessId = fulusConnectionState.selectedBusinessId;
      if (businessId != null) {
        await syncStatusNotifier.markRecoveryFailed(businessId, error);
        fulusConnectionState.markSyncError(error);
      }
    },
  );

  Future<void> initializeCloudSync() async {
    try {
      final session = await authApi.restoreServerSession(
      supabaseUrl: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
    if (session == null) return;
    fulusConnectionState.markSessionAuthenticated();
    await fulusConnectionState.refresh();
    final active = fulusConnectionState.membershipContext?.memberships.where((m) => m.status == 'active').toList(growable: false) ?? const [];
    if (active.isEmpty) return;

    // Preserve a previously selected active business across startup/session
    // restoration. Only choose automatically when there is exactly one active
    // membership; with multiple memberships, an already-valid selection is
    // sufficient and must not be discarded.
    final selectedBusinessId = fulusConnectionState.selectedBusinessId;
    if (selectedBusinessId == null) {
      if (active.length != 1) return;
      fulusConnectionState.selectBusiness(active.single.businessId);