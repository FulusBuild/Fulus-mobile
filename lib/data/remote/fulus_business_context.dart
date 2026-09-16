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
      final root = _asMap(response.data, 'Fulus Cloud response');
      final data = _asMap(root['data'], 'Fulus Cloud membership response');
      final raw = data['memberships'];
      if (raw != null && raw is! List) {
        throw const FormatException('Fulus Cloud returned invalid membership data.');
      }
      return FulusMembershipContext.fromJson(data, raw as List<dynamic>? ?? const []);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  static Map<String, dynamic> _asMap(Object? value, String label) {
    if (value is! Map) {
      throw FormatException('$label is unavailable or malformed.');
    }
    return Map<String, dynamic>.from(value);
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
  ) {
    final userId = data['user_id']?.toString();
    if (userId == null || userId.isEmpty) {
      throw const FormatException('Fulus Cloud did not return the signed-in user.');
    }

    final memberships = <FulusBusinessMembership>[];
    for (final item in raw) {
      if (item is! Map) {
        throw const FormatException('Fulus Cloud returned an invalid business membership.');
      }
      memberships.add(FulusBusinessMembership.fromJson(Map<String, dynamic>.from(item)));
    }

    return FulusMembershipContext(
      userId: userId,
      deviceClientId: data['device_client_id']?.toString(),
      memberships: memberships,
    );
  }
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

  factory FulusBusinessMembership.fromJson(Map<String, dynamic> json) {
    final businessId = json['business_id']?.toString();
    final status = json['status']?.toString();
    if (businessId == null || businessId.isEmpty) {
      throw const FormatException('Fulus Cloud returned a membership without a business.');
    }
    if (status == null || status.isEmpty) {
      throw const FormatException('Fulus Cloud returned a membership without a status.');
    }

    final joinedAtValue = json['joined_at'];
    final joinedAt = joinedAtValue == null
        ? null
        : DateTime.tryParse(joinedAtValue.toString());

    return FulusBusinessMembership(
      businessId: businessId,
      roleId: json['role_id']?.toString(),
      status: status,
      joinedAt: joinedAt,
    );
  }
}
