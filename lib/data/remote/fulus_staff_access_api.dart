import 'package:dio/dio.dart';

import 'api_client.dart';

/// Cloud staff/access boundary. All mutations are authorized server-side.
class FulusStaffAccessApi {
  FulusStaffAccessApi({required ApiClient client, required String functionBaseUrl})
      : _client = client, _functionBaseUrl = functionBaseUrl;

  final ApiClient _client;
  final String _functionBaseUrl;

  Future<StaffInvite> createInvite({
    required String businessId,
    required String roleName,
    required String email,
    required List<String> permissionCodes,
    int expiresHours = 24,
  }) async {
    final response = await _call({
      'action': 'create_invite',
      'business_id': businessId,
      'role_name': roleName,
      'email': email,
      'permission_codes': permissionCodes,
      'expires_hours': expiresHours,
    });
    return StaffInvite.fromJson(Map<String, dynamic>.from(response['data'] as Map));
  }

  Future<StaffClaim> claimInvite(String token) async {
    final response = await _call({'action': 'claim_invite', 'token': token});
    return StaffClaim.fromJson(Map<String, dynamic>.from(response['data'] as Map));
  }

  Future<bool> setMemberPermissions({
    required String businessId,
    required String userId,
    required List<String> permissionCodes,
  }) async {
    final response = await _call({
      'action': 'set_member_permissions',
      'business_id': businessId,
      'user_id': userId,
      'permission_codes': permissionCodes,
    });
    return response['data'] == true;
  }

  Future<bool> setMemberStatus({
    required String businessId,
    required String membershipId,
    required String status,
  }) async {
    final response = await _call({
      'action': 'set_member_status',
      'business_id': businessId,
      'membership_id': membershipId,
      'status': status,
    });
    return response['data'] == true;
  }

  Future<bool> changeMemberRole({
    required String businessId,
    required String membershipId,
    required String roleId,
  }) async {
    final response = await _call({
      'action': 'change_member_role',
      'business_id': businessId,
      'membership_id': membershipId,
      'role_id': roleId,
    });
    return response['data'] == true;
  }

  Future<bool> setRolePermission({
    required String businessId,
    required String roleId,
    required String permissionId,
    required bool enabled,
  }) async {
    final response = await _call({
      'action': 'set_role_permission',
      'business_id': businessId,
      'role_id': roleId,
      'permission_id': permissionId,
      'enabled': enabled,
    });
    return response['data'] == true;
  }

  Future<List<FulusDevice>> listDevices(String businessId) async {
    final response = await _call({'action': 'list_devices', 'business_id': businessId});
    final raw = response['data'] is List ? response['data'] as List : const [];
    return raw
        .map((item) => FulusDevice.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<bool> revokeDevice({
    required String businessId,
    required String deviceId,
  }) async {
    final response = await _call({
      'action': 'revoke_device',
      'business_id': businessId,
      'device_id': deviceId,
    });
    final result = response['data'];
    return result is Map && result['revoked'] == true;
  }

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    try {
      final response = await _client.dio.post(
        _functionBaseUrl,
        data: body,
        options: Options(headers: {
          'content-type': 'application/json',
          if (_client.serverAccessToken != null)
            'Authorization': 'Bearer ' + _client.serverAccessToken!,
        }),
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }
}

class StaffInvite {
  const StaffInvite({
    required this.inviteId,
    required this.token,
    required this.expiresAt,
  });

  final String inviteId;
  final String token;
  final DateTime expiresAt;

  factory StaffInvite.fromJson(Map<String, dynamic> json) => StaffInvite(
        inviteId: json['invite_id'] as String,
        token: json['token'] as String,
        expiresAt: DateTime.parse(json['expires_at'] as String),
      );
}

class StaffClaim {
  const StaffClaim({
    required this.businessId,
    required this.membershipId,
    required this.userId,
    required this.roleId,
    required this.roleName,
    required this.fullName,
    required this.email,
    required this.locationId,
    required this.permissionCodes,
  });

  final String businessId;
  final String membershipId;
  final String userId;
  final String roleId;
  final String roleName;
  final String fullName;
  final String email;
  final String? locationId;
  final List<String> permissionCodes;

  factory StaffClaim.fromJson(Map<String, dynamic> json) {
    final rawPermissions = json['permission_codes'];
    return StaffClaim(
      businessId: json['business_id'] as String,
      membershipId: json['membership_id'] as String,
      userId: json['user_id'] as String,
      roleId: json['role_id'] as String,
      roleName: (json['role_name'] as String? ?? 'cashier').toLowerCase(),
      fullName: (json['full_name'] as String? ?? '').trim(),
      email: (json['email'] as String? ?? '').trim().toLowerCase(),
      locationId: json['location_id']?.toString(),
      permissionCodes: rawPermissions is List
          ? rawPermissions.map((value) => value.toString()).toList(growable: false)
          : const [],
    );
  }
}

class FulusDevice {
  const FulusDevice({
    required this.id,
    required this.businessId,
    required this.deviceClientId,
    required this.status,
  });

  final String id;
  final String businessId;
  final String deviceClientId;
  final String status;

  factory FulusDevice.fromJson(Map<String, dynamic> json) => FulusDevice(
        id: json['id'] as String,
        businessId: json['business_id'] as String,
        deviceClientId: json['device_client_id'] as String,
        status: json['status'] as String,
      );
}
