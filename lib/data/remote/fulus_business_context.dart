import 'package:dio/dio.dart';

import 'api_client.dart';

/// Resolves the server memberships available to the currently connected
/// Supabase user and persists only the selected business ID locally.
class FulusBusinessContext {
  FulusBusinessContext({
    required ApiClient client,
    required String functionBaseUrl,
  })  : _client = client,
        _functionBaseUrl = functionBaseUrl;

  final ApiClient _client;
  final String _functionBaseUrl;

  Future<FulusMembershipContext> fetch() async {
    try {
      final response = await _client.dio.get(
        _functionBaseUrl,
        options: Options(headers: {
          'content-type': 'application/json',
          if (_client.serverAccessToken != null)
            'Authorization': 'Bearer ${_client.serverAccessToken}',
        }),
      );
      final root = Map<String, dynamic>.from(response.data as Map);
      final data = Map<String, dynamic>.from(root['data'] as Map);
      final raw = (data['memberships'] as List? ?? const []);
      return FulusMembershipContext.fromJson(data, raw);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }
}

class FulusMembershipContext {
  const FulusMembershipContext({
    required this.userId,
    required this.deviceClientId,
    required this.memberships,
  });

  final String userId;
  final String? deviceClientId;
  final List<FulusBusinessMembership> memberships;

  factory FulusMembershipContext.fromJson(
    Map<String, dynamic> data,
    List<dynamic> raw,
  ) =>
      FulusMembershipContext(
        userId: data['user_id'] as String,
        deviceClientId: data['device_client_id'] as String?,
        memberships: raw
            .map((item) => FulusBusinessMembership.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ))
            .toList(growable: false),
      );
}

class FulusBusinessMembership {
  const FulusBusinessMembership({
    required this.businessId,
    required this.roleId,
    required this.status,
    required this.joinedAt,
  });

  final String businessId;
  final String? roleId;
  final String status;
  final DateTime? joinedAt;

  factory FulusBusinessMembership.fromJson(Map<String, dynamic> json) =>
      FulusBusinessMembership(
        businessId: json['business_id'] as String,
        roleId: json['role_id'] as String?,
        status: json['status'] as String,
        joinedAt: json['joined_at'] == null
            ? null
            : DateTime.tryParse(json['joined_at'] as String),
      );
}
