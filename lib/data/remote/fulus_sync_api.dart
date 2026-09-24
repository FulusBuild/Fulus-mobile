import 'package:dio/dio.dart';

import '../../core/config/supabase_config.dart';
import 'api_client.dart';
import 'fulus_canonical_reconciler_typed.dart';
import '../../core/errors/failure.dart';
import '../../sync/sync_error.dart';

/// Client for the dedicated Fulus Supabase Edge Function.
class FulusSyncApi implements FulusCanonicalEntityFetcher, FulusCanonicalBatchEntityFetcher {
  FulusSyncApi({
    required ApiClient client,
    required String functionBaseUrl,
    String? canonicalStateFunctionUrl,
  })  : _client = client,
        _functionBaseUrl = functionBaseUrl,
        _canonicalStateFunctionUrl =
            canonicalStateFunctionUrl ??
                '${SupabaseConfig.url}/functions/v1/fulus-sync-state';

  final ApiClient _client;
  final String _functionBaseUrl;
  final String _canonicalStateFunctionUrl;

  Future<List<FulusCanonicalEntityResponse>> fetchCanonicalEntities({
    required String businessId,
    required String entityType,
    required List<String> entityIds,
    required String deviceClientId,
  }) async {
    if (entityIds.isEmpty) return const [];
    try {
      final response = await _client.dio.get(
        _canonicalStateFunctionUrl,
        queryParameters: {
          'business_id': businessId,
          'entity_type': entityType,
          'entity_ids': entityIds.join(','),
        },
        options: Options(headers: _headers(deviceClientId: deviceClientId)),
      );
      final root = Map<String, dynamic>.from(response.data as Map);
      final raw = root['data'];
      if (raw is! Map || raw['entities'] is! List) {
        throw const FormatException('Invalid canonical batch response.');
      }
      return (raw['entities'] as List)
          .map((item) => FulusCanonicalEntityResponse.fromJson({
                'data': Map<String, dynamic>.from(item as Map),
              }))
          .toList(growable: false);
    } on DioException catch (e) {
      throw _mapSyncTransportError(e);
    }
  }

  @override
  Future<FulusCanonicalEntityResponse> fetchCanonicalEntity({
    required String businessId,
    required String entityType,
    required String entityId,
    required String deviceClientId,
  }) async {
    try {
      final response = await _client.dio.get(
        _canonicalStateFunctionUrl,
        queryParameters: {
          'business_id': businessId,
          'entity_type': entityType,
          'entity_id': entityId,
        },
        options: Options(headers: _headers(deviceClientId: deviceClientId)),
      );
      return FulusCanonicalEntityResponse.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      throw _mapSyncTransportError(e);
    }
  }

  Future<FulusSyncPullResponse> pullChanges({
    required String businessId,
    int cursor = 0,
    int limit = 100,
  }) async {
    try {
      final response = await _client.dio.get(
        _functionBaseUrl,
        queryParameters: {
          'business_id': businessId,
          'cursor': cursor,
          'limit': limit,
        },
        options: Options(headers: _headers()),
      );
      return FulusSyncPullResponse.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  Future<Map<String, dynamic>> submitOperation({
    required String businessId,
    required String operationType,
    required String operationId,
    required String deviceClientId,
    String? clientReference,
    Object? payload,
  }) async {
    try {
      final rawPayload = payload is Map
          ? Map<String, dynamic>.from(payload)
          : <String, dynamic>{};
      final body = <String, dynamic>{
        'business_id': businessId,
        'operation_type': operationType,
        'operation_id': operationId,
        if (clientReference != null) 'client_reference': clientReference,
        'payload': payload,
      };

      if (operationType == 'sale.create' ||
          operationType == 'customer.create' ||
          operationType == 'customer.repayment' ||
          operationType == 'expense.create' ||
          operationType == 'return.create' ||
          operationType == 'stock_movement.create' ||
          operationType == 'stock_adjustment.create' ||
          operationType == 'location.create' ||
          operationType == 'income.create' ||
          operationType == 'expense_category.create' ||
          operationType == 'cash_drawer_shift.create' ||
          operationType == 'cash_drawer_shift.close') {
        body
          ..remove('operation_type')
          ..remove('payload')
          ..addAll(rawPayload)
          ..['action'] = switch (operationType) {
            'sale.create' => 'sale_create',
            'customer.create' => 'customer_create',
            'customer.repayment' => 'customer_repayment',
            'expense.create' => 'expense_create',
            'return.create' => 'return_create',
            'stock_movement.create' => 'inventory_adjust',
            'stock_adjustment.create' => 'inventory_set',
            'location.create' => 'location_create',
            'income.create' => 'income_create',
            'expense_category.create' => 'expense_category_create',
            'cash_drawer_shift.create' => 'cash_drawer_open',
            'cash_drawer_shift.close' => 'cash_drawer_close',
            _ => throw StateError('Unsupported Fulus operation: $operationType'),
          };
      }

      if (operationType == 'customer.update' ||
          operationType == 'expense.update') {
        body
          ..remove('operation_type')
          ..remove('payload')
          ..['action'] = switch (operationType) {
            'customer.update' => 'customer_update',
            'expense.update' => 'expense_update',
            _ => throw StateError('Unsupported Fulus operation: $operationType'),
          }
          ..['payload'] = rawPayload;
      }

      if (operationType.startsWith('product.') ||
          operationType.startsWith('category.') ||
          operationType.startsWith('supplier.')) {
        final dot = operationType.indexOf('.');
        final entity = operationType.substring(0, dot);
        final operation = operationType.substring(dot + 1);
        final apiEntity = switch (entity) {
          'product' => 'products',
          'category' => 'categories',
          'supplier' => 'suppliers',
          'expense_category' => 'expense_categories',
          _ => throw StateError('Unsupported catalog entity: $entity'),
        };
        body
          ..remove('operation_type')
          ..remove('payload')
          ..['action'] = operation == 'delete'
              ? 'catalog_delete'
              : 'catalog_upsert'
          ..['entity'] = apiEntity;
        if (operation == 'delete') {
          body['id'] = rawPayload['server_id'];
        } else {
          body['item'] = rawPayload;
          if (operation == 'update') body['id'] = rawPayload['server_id'];
        }
      }

      final response = await _client.dio.post(
        _functionBaseUrl,
        data: body,
        options: Options(headers: _headers(deviceClientId: deviceClientId)),
      );
      final result = Map<String, dynamic>.from(response.data as Map);
      return _normalizeOperationResponse(result, operationType: operationType);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  Object _mapSyncTransportError(DioException error) {
    final mapped = _client.mapError(error);
    // HTTP 429 is a server-side rate limit, not a permanent business-rule
    // rejection. Queue items must remain retryable so transient throttling
    // cannot permanently park financial or catalog work.
    if (error.response?.statusCode == 429) {
      return SyncFailure(
        kind: SyncErrorKind.temporaryServer,
        message: mapped is BusinessRuleFailure
            ? mapped.message
            : 'Cloud Sync was rate limited. Retrying automatically.',
        cause: mapped,
      );
    }
    return mapped;
  }

  Map<String, dynamic> _normalizeOperationResponse(
    Map<String, dynamic> result, {
    required String operationType,
  }) {
    final rawData = result['data'];
    if (rawData is! Map) return result;
    final data = Map<String, dynamic>.from(rawData);
    if (operationType == 'sale.create' && data['sale_id'] != null) {
      result['data'] = {...data, 'entity_id': data['sale_id']};
    } else if (operationType == 'customer.create' &&
        data['customer_id'] != null) {
      result['data'] = {...data, 'entity_id': data['customer_id']};
    } else if ((operationType.startsWith('product.') ||
            operationType.startsWith('category.') ||
            operationType.startsWith('supplier.') ||
            operationType.startsWith('expense_category.')) &&
        data['item'] is Map) {
      final item = Map<String, dynamic>.from(data['item'] as Map);
      result['data'] = {...data, 'entity_id': item['id'], 'entity': item};
    } else if (operationType == 'expense.create' && data['id'] != null) {
      result['data'] = {...data, 'entity_id': data['id']};
    } else if (operationType == 'return.create' && data['return_id'] != null) {
      result['data'] = {...data, 'entity_id': data['return_id']};
    } else if ((operationType == 'stock_movement.create' ||
            operationType == 'stock_adjustment.create') &&
        data['movement_id'] != null) {
      result['data'] = {...data, 'entity_id': data['movement_id']};
    } else if (operationType == 'location.create' && data['location_id'] != null) {
      result['data'] = {...data, 'entity_id': data['location_id']};
    } else if (operationType == 'income.create' && data['income_id'] != null) {
      result['data'] = {...data, 'entity_id': data['income_id']};
    } else if ((operationType == 'cash_drawer_shift.create' ||
            operationType == 'cash_drawer_shift.close') &&
        data['shift_id'] != null) {
      result['data'] = {...data, 'entity_id': data['shift_id']};
    }
    return result;
  }

  Map<String, String> _headers({String? deviceClientId}) => {
        'content-type': 'application/json',
        if (deviceClientId != null) 'x-fulus-device-id': deviceClientId,
        if (_client.serverAccessToken != null)
          'Authorization': 'Bearer ${_client.serverAccessToken}',
      };
}

class FulusCanonicalEntityResponse {
  const FulusCanonicalEntityResponse({required this.data});

  final Map<String, dynamic> data;

  String get entityType => data['entity_type'] as String;
  String get entityId => data['entity_id'] as String;
  String get operation => data['operation'] as String;

  factory FulusCanonicalEntityResponse.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    if (rawData is! Map) {
      throw const FormatException('Invalid canonical sync response.');
    }
    return FulusCanonicalEntityResponse(
      data: Map<String, dynamic>.from(rawData),
    );
  }
}

class FulusSyncPullResponse {
  const FulusSyncPullResponse({
    required this.changes,
    required this.cursor,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<FulusSyncChange> changes;
  final int cursor;
  final int nextCursor;
  final bool hasMore;

  factory FulusSyncPullResponse.fromJson(Map<String, dynamic> json) {
    final data = Map<String, dynamic>.from(json['data'] as Map);
    final rawChanges = data['changes'] as List? ?? const [];
    return FulusSyncPullResponse(
      changes: rawChanges
          .map((item) => FulusSyncChange.fromJson(
                Map<String, dynamic>.from(item as Map),
              ))
          .toList(growable: false),
      cursor: (data['cursor'] as num).toInt(),
      nextCursor: (data['next_cursor'] as num).toInt(),
      hasMore: data['has_more'] as bool? ?? false,
    );
  }
}

class FulusSyncChange {
  const FulusSyncChange({
    required this.sequence,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.createdAt,
  });

  final int sequence;
  final String entityType;
  final String entityId;
  final String operation;
  final Object? payload;
  final DateTime createdAt;

  factory FulusSyncChange.fromJson(Map<String, dynamic> json) =>
      FulusSyncChange(
        sequence: (json['sequence'] as num).toInt(),
        entityType: json['entity_type'] as String,
        entityId: json['entity_id'] as String,
        operation: json['operation'] as String,
        payload: json['payload'],
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
