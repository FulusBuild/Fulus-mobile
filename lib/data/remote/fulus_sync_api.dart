import 'package:dio/dio.dart';

import '../api_client.dart';

/// Client for the dedicated Fulus Supabase Edge Function.
///
/// This is intentionally separate from the legacy FastAPI-style endpoint
/// classes in this repository. The Fulus cloud API is the server-authoritative
/// sync boundary and speaks in sync cursors/operations rather than screen-level
/// CRUD calls.
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
      final response = await Dio(BaseOptions(baseUrl: _functionBaseUrl)).get(
        '',
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
      final response = await Dio(BaseOptions(baseUrl: _functionBaseUrl)).post(
        '',
        data: {
          'business_id': businessId,
          'operation_type': operationType,
          'operation_id': operationId,
          if (clientReference != null) 'client_reference': clientReference,
          'payload': payload,
        },
        options: Options(headers: _headers(deviceClientId: deviceClientId)),
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
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
