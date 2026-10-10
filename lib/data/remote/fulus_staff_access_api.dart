import 'package:dio/dio.dart';

import 'api_client.dart';

/// Cloud staff/access boundary. All mutations are authorized server-side.
class FulusStaffAccessApi {
  FulusStaffAccessApi({
    required ApiClient client,
    required String functionBaseUrl,
    String? ownershipFunctionBaseUrl,
  })  : _client = client,
        _functionBaseUrl = functionBaseUrl,
        _ownershipFunctionBaseUrl = ownershipFunctionBaseUrl ??
            functionBaseUrl.replaceFirst('/fulus-staff-api', '/fulus-api');

  final ApiClient _client;
  final String _functionBaseUrl;
  final String _ownershipFunctionBaseUrl;

  Future<StaffInvite> createInvite({
    required String businessId,
    required String roleName,
    required String email,
    List<String>? permissionCodes,
    String? locationId,
    String? invitedName,
    String? employeeClientReference,
    Map<String, dynamic>? employee,
    int expiresHours = 24,
  }) async {
    final response = await _call({
      'action': 'create_invite',
      'business_id': businessId,
      'role_name': roleName,
      'email': email,
      'permission_codes': permissionCodes,
      if (locationId != null) 'location_id': locationId,
      if (invitedName != null && invitedName.trim().isNotEmpty) 'invited_name': invitedName.trim(),
      if (employeeClientReference != null) 'employee_client_reference': employeeClientReference,
      if (employee != null) 'employee': employee,
      'expires_hours': expiresHours,
    });
    return StaffInvite.fromJson(Map<String, dynamic>.from(response['data'] as Map));
  }

  Future<StaffInvitePreview> inspectInvite(String token) async {
    final response = await _call({
      'action': 'inspect_invite',
      'token': token.trim(),
    });
    return StaffInvitePreview.fromJson(
      Map<String, dynamic>.from(response['data'] as Map),
    );
  }

  Future<void> prepareInvitedAccount({required String token, required String password}) async {
    await _call({
      'action': 'prepare_invited_account',
      'token': token.trim(),
      'password': password,
    });
  }

  Future<StaffClaim> claimInvite(String token, {String? fullName}) async {
    final response = await _call({
      'action': 'claim_invite',
      'token': token,
      if (fullName != null && fullName.trim().isNotEmpty) 'full_name': fullName.trim(),
    });
    return StaffClaim.fromJson(Map<String, dynamic>.from(response['data'] as Map));
  }

  Future<StaffClaim> getMyAccess({required String businessId}) async {
    final response = await _call({
      'action': 'get_my_access',
      'business_id': businessId,
    });
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

  Future<bool> revokePendingInvitesByEmail({
    required String businessId,
    required String email,
  }) async {
    final response = await _call({
      'action': 'revoke_pending_invites_by_email',
      'business_id': businessId,
      'email': email.trim().toLowerCase(),
    });
    return response['data'] == true;
  }

  Future<bool> setMemberStatusByEmail({
    required String businessId,
    required String email,
    required String status,
  }) async {
    final response = await _call({
      'action': 'set_member_status_by_email',
      'business_id': businessId,
      'email': email.trim().toLowerCase(),
      'status': status,
    });
    return response['data'] == true;
  }

  Future<bool> setMemberStatusByUser({
    required String businessId,
    required String userId,
    required String status,
  }) async {
    final response = await _call({
      'action': 'set_member_status_by_user',
      'business_id': businessId,
      'user_id': userId,
      'status': status,
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

  /// Lists unresolved legacy product/customer ownership reviews. The server
  /// independently enforces owner/admin membership for this business.
  Future<List<LocationOwnershipReview>> listLocationOwnershipReviews({
    required String businessId,
  }) async {
    final response = await _call({
      'action': 'location_ownership_review_list',
      'business_id': businessId,
    }, functionBaseUrl: _ownershipFunctionBaseUrl);
    final data = response['data'];
    final raw = data is Map ? data['items'] : null;
    if (raw is! List) {
      throw const FormatException('Cloud returned invalid ownership review data.');
    }
    return raw
        .map((item) => LocationOwnershipReview.fromJson(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList(growable: false);
  }

  /// Lists active locations from the same server-validated business context
  /// used by the ownership review API. Do not use the local location cache here:
  /// it has no business_id column and may contain locations from another account.
  Future<List<LocationOwnershipTarget>> listLocationOwnershipTargets({
    required String businessId,
  }) async {
    final response = await _call({
      'action': 'location_ownership_review_list',
      'business_id': businessId,
    }, functionBaseUrl: _ownershipFunctionBaseUrl);
    final data = response['data'];
    final raw = data is Map ? data['locations'] : null;
    if (raw is! List) {
      throw const FormatException('Cloud returned invalid ownership location data.');
    }
    return raw
        .map((item) => LocationOwnershipTarget.fromJson(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList(growable: false);
  }

  /// Resolves one pending review to an explicitly selected location. This
  /// never guesses ownership; the server revalidates role, business,
  /// location, and unresolved-record state in one transaction.
  Future<void> resolveLocationOwnershipReview({
    required String businessId,
    required String reviewId,
    required String locationId,
  }) async {
    await _call({
      'action': 'location_ownership_review_resolve',
      'business_id': businessId,
      'review_id': reviewId,
      'location_id': locationId,
    }, functionBaseUrl: _ownershipFunctionBaseUrl);
  }

  Future<Map<String, dynamic>> _call(
    Map<String, dynamic> body, {
    String? functionBaseUrl,
  }) async {
    try {
      final response = await _client.dio.post(
        functionBaseUrl ?? _functionBaseUrl,
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

class LocationOwnershipTarget {
  const LocationOwnershipTarget({required this.id, required this.name});

  final String id;
  final String name;

  factory LocationOwnershipTarget.fromJson(Map<String, dynamic> json) =>
      LocationOwnershipTarget(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
      );
}

class LocationOwnershipReview {
  const LocationOwnershipReview({
    required this.id,
    required this.businessId,
    required this.entityType,
    required this.entityId,
    required this.candidateLocationIds,
    required this.classification,
    required this.reason,
    required this.createdAt,
  });

  final String id;
  final String businessId;
  final String entityType;
  final String entityId;
  final List<String> candidateLocationIds;
  final String classification;
  final String reason;
  final DateTime? createdAt;

  String get displayEntityType =>
      entityType == 'product' ? 'Product' :
      entityType == 'customer' ? 'Customer' :
      entityType == 'employee' ? 'Employee' : entityType;

  factory LocationOwnershipReview.fromJson(Map<String, dynamic> json) {
    final candidates = json['candidate_location_ids'];
    return LocationOwnershipReview(
      id: json['id']?.toString() ?? '',
      businessId: json['business_id']?.toString() ?? '',
      entityType: json['entity_type']?.toString() ?? 'record',
      entityId: json['entity_id']?.toString() ?? '',
      candidateLocationIds: candidates is List
          ? candidates.map((value) => value.toString()).toList(growable: false)
          : const [],
      classification: json['classification']?.toString() ?? 'unresolved',
      reason: json['reason']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }
}

class StaffInvitePreview {
  const StaffInvitePreview({
    required this.businessId,
    required this.businessName,
    required this.fullName,
    required this.email,
    required this.roleName,
    required this.expiresAt,
    this.locationId,
  });

  final String businessId;
  final String businessName;
  final String fullName;
  final String email;
  final String roleName;
  final DateTime expiresAt;
  final String? locationId;

  factory StaffInvitePreview.fromJson(Map<String, dynamic> json) => StaffInvitePreview(
        businessId: json['business_id'] as String,
        businessName: (json['business_name'] as String? ?? 'your business').trim(),
        fullName: (json['full_name'] as String? ?? '').trim(),
        email: (json['email'] as String? ?? '').trim().toLowerCase(),
        roleName: (json['role_name'] as String? ?? 'employee').trim().toLowerCase(),
        expiresAt: DateTime.parse(json['expires_at'] as String),
        locationId: json['location_id']?.toString(),
      );
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
    this.employeeId,
    this.employee,
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
  final String? employeeId;
  final Map<String, dynamic>? employee;

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
      employeeId: json['employee_id']?.toString(),
      employee: json['employee'] is Map ? Map<String, dynamic>.from(json['employee'] as Map) : null,
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
