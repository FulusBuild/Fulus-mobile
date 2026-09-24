import 'fulus_sync_api.dart';

abstract interface class FulusCanonicalEntityFetcher {
  Future<FulusCanonicalEntityResponse> fetchCanonicalEntity({
    required String businessId,
    required String entityType,
    required String entityId,
    required String deviceClientId,
  });
}

abstract interface class FulusCanonicalBatchEntityFetcher {
  static const maxBatchSize = 100;

  Future<List<FulusCanonicalEntityResponse>> fetchCanonicalEntities({
    required String businessId,
    required String entityType,
    required List<String> entityIds,
    required String deviceClientId,
  });
}

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

    var start = 0;
    while (start < changes.length) {
      final entityType = changes[start].entityType;
      var end = start + 1;
      while (end < changes.length && changes[end].entityType == entityType) {
        end++;
      }

      final group = changes.sublist(start, end);
      const batchable = {
        'customer', 'category', 'supplier', 'expense_category', 'expense',
        'income_record', 'cash_drawer_shift', 'location',
        'customer_ledger', 'stock_movement',
      };

      if (!batchable.contains(entityType) || group.length == 1) {
        for (final change in group) {
          await reconcile(change, businessId: businessId, deviceClientId: deviceClientId);
        }
      } else {
        for (var offset = 0;
            offset < group.length;
            offset += FulusCanonicalBatchEntityFetcher.maxBatchSize) {
          final chunk = group
              .skip(offset)
              .take(FulusCanonicalBatchEntityFetcher.maxBatchSize)
              .toList(growable: false);
          final entityIds = <String>{
            for (final change in chunk) change.entityId,
          }.toList(growable: false);

          final responses = await batchFetcher.fetchCanonicalEntities(
            businessId: businessId,
            entityType: entityType,
            entityIds: entityIds,
            deviceClientId: deviceClientId,
          );
          final byId = {
            for (final response in responses) response.entityId: response,
          };
          if (responses.length != entityIds.length ||
              byId.length != entityIds.length ||
              byId.keys.any((id) => !entityIds.contains(id))) {
            throw StateError(
              'Canonical batch response does not exactly match the requested IDs.',
            );
          }

          for (final change in chunk) {
            final response = byId[change.entityId];
            if (response == null) {
              throw StateError(
                'Canonical batch response omitted ' +
                change.entityType + ':' + change.entityId,
              );
            }
            await applyCanonicalResponse(
              response,
              expectedEntityType: change.entityType,
              expectedEntityId: change.entityId,
            );
          }
        }
      }
      start = end;
    }
  }

  Future<void> reconcile(
    FulusSyncChange change, {
    required String businessId,
    required String deviceClientId,
  }) async {
    final canonical = await fetchCanonical(
      change,
      businessId: businessId,
      deviceClientId: deviceClientId,
    );
    await applyCanonicalResponse(
      canonical,
      expectedEntityType: change.entityType,
      expectedEntityId: change.entityId,
    );
  }

  Future<FulusCanonicalEntityResponse> fetchCanonical(
    FulusSyncChange change, {
    required String businessId,
    required String deviceClientId,
  }) async {
    if (!_handlers.containsKey(change.entityType)) {
      throw StateError('Unsupported canonical sync entity: ' + change.entityType);
    }
    if (change.operation != 'upsert' && change.operation != 'delete') {
      throw StateError('Unsupported server sync operation: ' + change.operation);
    }

    final canonical = await _api.fetchCanonicalEntity(
      businessId: businessId,
      entityType: change.entityType,
      entityId: change.entityId,
      deviceClientId: deviceClientId,
    );
    _validateCanonicalResponse(
      canonical,
      expectedEntityType: change.entityType,
      expectedEntityId: change.entityId,
    );
    return canonical;
  }

  Future<void> applyCanonicalResponse(
    FulusCanonicalEntityResponse canonical, {
    required String expectedEntityType,
    required String expectedEntityId,
  }) async {
    _validateCanonicalResponse(
      canonical,
      expectedEntityType: expectedEntityType,
      expectedEntityId: expectedEntityId,
    );
    final handler = _handlers[expectedEntityType];
    if (handler == null) {
      throw StateError('Unsupported canonical sync entity: ' + expectedEntityType);
    }
    await handler(canonical);
  }

  void _validateCanonicalResponse(
    FulusCanonicalEntityResponse canonical, {
    required String expectedEntityType,
    required String expectedEntityId,
  }) {
    if (canonical.entityType != expectedEntityType ||
        canonical.entityId != expectedEntityId) {
      throw StateError('Canonical sync response does not match the change.');
    }
    if (canonical.operation != 'upsert' && canonical.operation != 'delete') {
      throw StateError(
        'Canonical sync response returned unsupported operation: ' +
        canonical.operation,
      );
    }
  }
}
