    } catch (error, stackTrace) {
      _onSyncFailure?.call(error, stackTrace);
      rethrow;
    }
  }

  Future<void> _runSyncCycle({bool manual = false}) async {
    await _syncEngine.runOnce(manual: manual);
    await _onPushSuccess?.call();
    final pull = _pullFromServer;
    if (pull != null) {
      // Pull failures are intentionally propagated. A reconciliation failure
      // is a real sync failure and must remain observable to the caller and
      // diagnostic layer rather than being silently converted into success.
      var recoveredFromStaleCursor = false;
      try {
        await pull();
      } on BusinessRuleFailure catch (error) {
        if (error.code != 'SYNC_CURSOR_TOO_OLD') rethrow;
        final recover = _onCursorTooOldRecovery;
        if (recover == null) rethrow;
        await recover();
        recoveredFromStaleCursor = true;
        try {
          await pull();
        } catch (error) {
          await _onRecoveryFailed?.call(error);
          rethrow;
        }
      }
      // Recovery deliberately clears Sync Ready while bootstrap replaces local
      // cloud-owned state. Readiness is restored only after the post-bootstrap
      // delta pull succeeds, so the UI can never advertise readiness before
      // authoritative reconciliation has completed.
      if (recoveredFromStaleCursor) {
        try {
          await _onRecoveryReconciled?.call();
        } catch (error) {
          await _onRecoveryFailed?.call(error);
          rethrow;
        }
      }
    }
  }

  bool _hasConnectivity(List<ConnectivityResult> results) =>