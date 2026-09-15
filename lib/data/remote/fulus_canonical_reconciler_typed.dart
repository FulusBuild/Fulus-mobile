import 'fulus_sync_api.dart';

/// Routes canonical server state to entity-owned reconciliation callbacks.
///
/// This class intentionally has no knowledge of Drift tables or SQL. Each
/// callback owns the local persistence semantics for its entity and must only
/// complete after its local reconciliation has completed successfully.
class FulusCanonicalTypedReconciler {
  FulusCanonicalTypedReconciler({
    required FulusSyncApi api,
    required Map<String, Future<void> Function(FulusCanonicalEntityResponse)> handlers,
  })  : _api = api,
        _handlers = Map.unmodifiable(handlers);

  final FulusSyncApi _api;
  final Map<String, Future<void> Function(FulusCanonicalEntityResponse)> _handlers;

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
