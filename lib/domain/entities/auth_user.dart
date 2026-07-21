import 'package:json_annotation/json_annotation.dart';

part 'auth_user.g.dart';

/// The domain-facing "who's logged in" representation — Architecture
/// Section 6. Deliberately does NOT include either token: the access
/// token lives in memory only, inside ApiClient's auth interceptor, and
/// the refresh token lives only in SecureStorage — neither is a
/// domain/UI concern. Mirrors backend/app/schemas/auth.py's UserOut,
/// verified directly.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.username,
    required this.email,
    required this.fullName,
    required this.role,
    required this.isActive,
  });

  final String id;
  final String username;
  final String email;
  final String fullName;

  /// Kept as a plain String (backend values: admin/manager/staff/cashier
  /// — verified directly against backend/app/models/user.py's UserRole
  /// enum), not a Dart enum, since nothing in this phase branches on
  /// role yet — Volume 3's role-gated UI is what would actually need
  /// that, and isn't built here. A reasonable simplification to revisit
  /// then, not an oversight now.
  final String role;
  final bool isActive;
}

/// POST /api/auth/login's body — request-only, mirrors LoginRequest
/// exactly (backend/app/schemas/auth.py, verified directly).
@JsonSerializable(fieldRename: FieldRename.snake, createFactory: false)
class LoginRequestDto {
  const LoginRequestDto({required this.username, required this.password});

  final String username;
  final String password;

  Map<String, dynamic> toJson() => _$LoginRequestDtoToJson(this);
}

/// POST /api/auth/refresh's body — request-only, mirrors RefreshRequest
/// exactly.
@JsonSerializable(fieldRename: FieldRename.snake, createFactory: false)
class RefreshRequestDto {
  const RefreshRequestDto({required this.refreshToken});

  final String refreshToken;

  Map<String, dynamic> toJson() => _$RefreshRequestDtoToJson(this);
}

/// The response shape both /login and /refresh share — mirrors
/// TokenResponse exactly (verified directly: both routes declare
/// response_model=TokenResponse in backend/app/routers/auth.py, and
/// refresh_access_token in auth_service.py returns a brand-new
/// refresh_token on every call — refresh token ROTATION, not reuse —
/// which is exactly why AuthRepositoryImpl always re-stores
/// response.refreshToken rather than assuming it's unchanged).
/// Response-only: createToJson: false, mirroring the same pattern
/// already established for Sale's response DTOs in sale.dart.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class TokenResponseDto {
  const TokenResponseDto({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final UserDto user;

  factory TokenResponseDto.fromJson(Map<String, dynamic> json) =>
      _$TokenResponseDtoFromJson(json);
}

/// Mirrors UserOut exactly (backend/app/schemas/auth.py).
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class UserDto {
  const UserDto({
    required this.id,
    required this.username,
    required this.email,
    required this.fullName,
    required this.role,
    required this.isActive,
  });

  final String id;
  final String username;
  final String email;
  final String fullName;
  final String role;
  final bool isActive;

  factory UserDto.fromJson(Map<String, dynamic> json) => _$UserDtoFromJson(json);

  AuthUser toDomain() => AuthUser(
        id: id,
        username: username,
        email: email,
        fullName: fullName,
        role: role,
        isActive: isActive,
      );
}
