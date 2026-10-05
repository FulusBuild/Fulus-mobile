import 'package:dio/dio.dart';

import '../../sync/sync_actor_context.dart';

import '../../core/config/supabase_config.dart';
import 'api_client.dart';
import 'fulus_canonical_reconciler_typed.dart';
import 'fulus_sync_operation_serializer.dart';
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
  final FulusSyncOperationSerializer _operationSerializer =
      const FulusSyncOperationSerializer();

  Future<List<FulusCanonicalEntityResponse>> fetchCanonicalEntities({
    required String businessId,
    required String entityType,
    required List<String> entityIds,
    required String deviceClientId,
  }) async {
    if (entityIds.isEmpty) return const [];
    try {
      final response = await _requestAsSyncActor(
        'GET',
        _canonicalStateFunctionUrl,
        queryParameters: {
          'business_id': businessId,
          'entity_type': entityType,
          'entity_ids': entityIds.join(','),
        },
        deviceClientId: deviceClientId,
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
      final response = await _requestAsSyncActor(
        'GET',
        _canonicalStateFunctionUrl,
        queryParameters: {
          'business_id': businessId,
          'entity_type': entityType,
          'entity_id': entityId,
        },
        deviceClientId: deviceClientId,
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
      final response = await _requestAsSyncActor(
        'GET',
        _functionBaseUrl,
        queryParameters: {
          'business_id': businessId,
          'cursor': cursor,
          'limit': limit,
        },
      );
      return FulusSyncPullResponse.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      throw _mapSyncTransportError(e);
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
      final body = _operationSerializer.serialize(
        businessId: businessId,
        operationType: operationType,
        operationId: operationId,
        clientReference: clientReference,
        payload: payload,
      );

      final response = await _requestAsSyncActor(
        'POST',
        _functionBaseUrl,
        data: body,
        deviceClientId: deviceClientId,
      );
      final result = Map<String, dynamic>.from(response.data as Map);
      return _operationSerializer.normalizeResponse(
        result,
        operationType: operationType,
      );
    } on DioException catch (e) {
      throw _mapSyncTransportError(e);
    }
  }

  Future<Response<dynamic>> _requestAsSyncActor(
    String method,
    String url, {
    Map<String, dynamic>? queryParameters,
    Object? data,
    String? deviceClientId,
  }) async {
    final actorUserId = currentSyncActorUserId();
    final useActiveSession =
        actorUserId == null || actorUserId == _client.activeCloudUserId;

    if (useActiveSession) {
      return _client.dio.request(
        url,
        queryParameters: queryParameters,
        data: data,
        options: Options(
          method: method,
          headers: _headers(deviceClientId: deviceClientId),
        ),
      );
    }

    Future<Response<dynamic>> send(String token) {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
      ));
      return dio.request(
        url,
        queryParameters: queryParameters,
        data: data,
        options: Options(
          method: method,
          headers: _headers(
            deviceClientId: deviceClientId,
            accessToken: token,
          ),
        ),
      );
    }

    final token = await _client.accessTokenForUser(actorUserId);
    if (token == null) {
      throw const AuthFailure.sessionExpired();
    }
    try {
      return await send(token);
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) rethrow;
      final refreshed = await _client.accessTokenForUser(actorUserId, forceRefresh: true);
      if (refreshed == null) throw const AuthFailure.sessionExpired();
      return send(refreshed);
    }
  }

  Object _mapSyncTransportError(DioException error) {
    final mapped = _client.mapError(error);
    // HTTP 408 is a transient request timeout and HTTP 429 is a server-side
    // rate limit. Neither is a permanent business-rule rejection. Queue items must remain retryable so transient throttling
    // cannot permanently park financial or catalog work.
    if (error.response?.statusCode == 408 ||
        error.response?.statusCode == 429) {
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

  Map<String, String> _headers({
    String? deviceClientId,
    String? accessToken,
  }) {
    final token = accessToken ?? _client.serverAccessToken;
    return {
      'content-type': 'application/json',
      if (deviceClientId != null) 'x-fulus-device-id': deviceClientId,
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }
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
