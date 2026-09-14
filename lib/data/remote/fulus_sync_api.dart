import 'package:dio/dio.dart';

import 'api_client.dart';

/// Client for the dedicated Fulus Supabase Edge Function.
class FulusSyncApi {
  FulusSyncApi({
    required ApiClient client,
    required String functionBaseUrl,
  })  : _client = client,
        _functionBaseUrl = functionBaseUrl;

  final ApiClient _client;
  final String _functionBaseUrl;

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

      if (operationType == 'sale.create') {
        body
          ..remove('operation_type')
          ..remove('payload')
          ..addAll(rawPayload)
          ..['action'] = 'sale_create';
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
          _ => throw StateError('Unsupported catalog entity: $entity'),
        };
        body
          ..remove('operation_type')
          ..remove('payload')
          ..['action'] = operation == 'delete' ? 'catalog_delete' : 'catalog_upsert'
          ..['entity'] = apiEntity;
        if (operation == 'delete') {
          body['id'] = rawPayload['server_id'];
        } else {
          body['item'] = rawPayload;
          if (operation == 'update') {
            body['id'] = rawPayload['server_id'];
          }
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

  Map<String, dynamic> _normalizeOperationResponse(
    Map<String, dynamic> result, {
    required String operationType,
  }) {
    final rawData = result['data'];
    if (rawData is! Map) return result;

    final data = Map<String, dynamic>.from(rawData);
    if (operationType == 'sale.create' && data['sale_id'] != null) {
      result['data'] = {...data, 'entity_id': data['sale_id']};
    } else if ((operationType.startsWith('product.') ||
            operationType.startsWith('category.') ||
            operationType.startsWith('supplier.')) &&
        data['item'] is Map) {
      final item = Map<String, dynamic>.from(data['item'] as Map);
      result['data'] = {...data, 'entity_id': item['id'], 'entity': item};
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
    final rawChanges = (data['changes'] as List? ?? const []);
    return FulusSyncPullResponse(
      changes: rawChanges
          .map((item) => FulusSyncChange.fromJson(Map<String, dynamic>.from(item as Map)))
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

  factory FulusSyncChange.fromJson(Map<String, dynamic> json) => FulusSyncChange(
        sequence: (json['sequence'] as num).toInt(),
        entityType: json['entity_type'] as String,
        entityId: json['entity_id'] as String,
        operation: json['operation'] as String,
        payload: json['payload'],
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
