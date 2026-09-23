    }
  }

  syncTriggers = SyncTriggers(
    syncEngine: syncEngine,
    syncConfig: syncConfig,
    syncStatusNotifier: syncStatusNotifier,
    isReady: () async => fulusConnectionState.isSyncReady,
    onNotReady: initializeCloudSync,
    onSyncSuccess: () {
      fulusConnectionState.clearSyncError();
      // A successful push + pull proves that authentication, business
      // membership, device authorization, and canonical reconciliation are
      // working again. Promote the connection back to Sync Ready even when
      // the previous cycle failed after readiness had been established.
      if (fulusConnectionState.isSessionAuthenticated &&
          fulusConnectionState.selectedBusinessId != null &&
          fulusConnectionState.isDeviceAuthorized) {
        fulusConnectionState.markSyncReady();
      }
    },
    onCursorTooOldRecovery: () async {
      final businessId = fulusConnectionState.selectedBusinessId;
      if (businessId == null) {
        throw StateError('Fulus Cloud business context is missing during cursor recovery.');
      }
      await syncRecovery.recover(businessId: businessId);
    },
    onRecoveryReconciled: () async {
      final businessId = fulusConnectionState.selectedBusinessId;
      if (businessId != null) {
        await syncStatusNotifier.markRecoveryCompleted(businessId);
      }
      fulusConnectionState.markSyncReady();
    },
    onRecoveryFailed: (error) async {
      final businessId = fulusConnectionState.selectedBusinessId;
      if (businessId != null) {
        await syncStatusNotifier.markRecoveryFailed(businessId, error);
      }
      fulusConnectionState.markSyncError(error);
    },
    onPushSuccess: () async {
      final businessId = fulusConnectionState.selectedBusinessId;
      if (businessId != null) {
        await syncStatusNotifier.recordPushSuccess(businessId);
      }
    },
    onSyncFailure: (error, _) => fulusConnectionState.markSyncError(error),
    pullFromServer: () async {
      if (!syncConfig.isEnabled) return;
      final businessId = fulusConnectionState.selectedBusinessId;
      final registeredDevice = fulusConnectionState.registeredDevice;
      if (businessId == null || registeredDevice == null || !fulusConnectionState.isDeviceAuthorized) {
        throw StateError('Fulus Cloud is not ready for canonical pull.');
      }
      // Never apply inbound canonical state while an unresolved local
      // optimistic-concurrency conflict exists. The rejected local mutation
      // must remain visible until the user explicitly resolves it; otherwise
      // a later pull could silently overwrite the local edit before resolution.
      if (await syncStatusNotifier.unresolvedConflictCount() > 0) {
        throw const BusinessRuleFailure(
          'Cloud pull is paused until the pending local sync conflict is resolved.',
          code: 'SYNC_CONFLICT_PENDING',
        );
      }
      final cursor = await syncCoordinator.pullAndApply(businessId: businessId);
      await syncStatusNotifier.recordPullSuccess(businessId, cursor);