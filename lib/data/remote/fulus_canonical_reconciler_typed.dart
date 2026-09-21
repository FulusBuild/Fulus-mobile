import 'fulus_sync_api.dart';

/// Minimal transport contract needed by canonical reconciliation.
///
/// Keeping this boundary separate from the concrete HTTP client makes the
/// reconciliation layer independently testable and keeps transport concerns
/// out of entity-owned persistence callbacks.
abstract interface class FulusCanonicalEntityFetcher {
  Future<FulusCanonicalEntityResponse> fetchCanonicalEntity({
    required String businessId,
    required String entityType,
    required String entityId,
    required String deviceClientId,
  });
}

/// Routes canonical server state to entity-owned reconciliation callbacks.
///
/// This class intentionally has no knowledge of Drift tables or SQL. Each
/// callback owns the local persistence semantics for its entity and must only
/// complete after its local reconciliation has completed successfully.
class FulusCanonicalTypedReconciler {
  FulusCanonicalTypedReconciler({
    required FulusCanonicalEntityFetcher api,
    required Map<String, Future<void> Function(FulusCanonicalEntityResponse)> handlers,
  })  : _api = api,
        _handlers = Map.unmodifiable(handlers);

  final FulusCanonicalEntityFetcher _api;
  final Map<String, Future<void> Function(FulusCanonicalEntityResponse)> _handlers;

  Future<void> reconcileChanges(
    List<FulusSyncChange> changes, {
    required String businessId,
    required String deviceClientId,
  }) async {
    if (changes.isEmpty) return;
    final batchFetcher = _api is FulusCanonicalBatchEntityFetcher
        ? _api as FulusCanonicalBatchEntityFetcher
        : null;
    if (batchFetcher == null) {
      for (final change in changes) {
        await reconcile(change, businessId: businessId, deviceClientId: deviceClientId);
      }
      return;
    }
    final grouped = <String, List<FulusSyncChange>>{};
    for (final change in changes) {
      grouped.putIfAbsent(change.entityType, () => <FulusSyncChange>[]).add(change);
    }
    for (final entry in grouped.entries) {
      final entityType = entry.key;
      final group = entry.value;
      const batchable = {
        'customer', 'category', 'supplier', 'expense_category', 'expense',
        'income_record', 'cash_drawer_shift', 'location', 'customer_ledger',
        'stock_movement',
      };
      if (!batchable.contains(entityType) || group.length == 1) {
        for (final change in group) {
          await reconcile(change, businessId: businessId, deviceClientId: deviceClientId);
        }
        continue;
      }
      final responses = await batchFetcher.fetchCanonicalEntities(
        businessId: businessId,
        entityType: entityType,
        entityIds: group.map((change) => change.entityId).toSet().toList(),
        deviceClientId: deviceClientId,
      );
      final byId = {for (final response in responses) response.entityId: response};
      for (final change in group) {
        final response = byId[change.entityId];
        if (response == null) {
          throw StateError('Canonical batch response omitted ' + change.entityType + ':' + change.entityId);
        }
        final handler = _handlers[change.entityType];
        if (handler == null) {
          throw StateError('Unsupported canonical sync entity: ' + change.entityType);
        }
        if (response.entityType != change.entityType || response.entityId != change.entityId) {
          throw StateError('Canonical batch response does not match the change.');
        }
        await handler(response);
      }
    }
  }

  Future<void> reconcile(
    FulusSyncChange change, {
    required String businessId,
    required String deviceClientId,
  }) async {
    final handler = _handlers[change.entityType];
    if (handler == null) {
      throw StateError('Unsupported canonical sync entity: ${change.entityType}');
    }
    if (change.operation != 'upsert' && change.operation != 'delete') {
      throw StateError('Unsupported server sync operation: ${change.operation}');
    }

    final canonical = await _api.fetchCanonicalEntity(
      businessId: businessId,
      entityType: change.entityType,
      entityId: change.entityId,
      deviceClientId: deviceClientId,
    );

    if (canonical.entityType != change.entityType ||
        canonical.entityId != change.entityId) {
      throw StateError('Canonical sync response does not match the change.');
    }

    if (canonical.operation != 'upsert' && canonical.operation != 'delete') {
      throw StateError(
        'Canonical sync response returned unsupported operation: ${canonical.operation}',
      );
    }

    await handler(canonical);
  }
}
