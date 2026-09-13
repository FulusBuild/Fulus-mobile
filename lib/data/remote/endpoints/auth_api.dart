import 'package:dio/dio.dart';

import '../../../domain/entities/approval_hash.dart';
import '../api_client.dart';

class AuthApi {
  AuthApi(this._client);

  static const emailVerificationRedirect = 'fulus://auth/callback';
  final ApiClient _client;

  Future<void> setApprovalPin({required String pinHash, required String pinSalt}) async {
    try {
      await _client.dio.post('/api/auth/approval-pin', data: SetApprovalPinRequestDto(pinHash: pinHash, pinSalt: pinSalt).toJson());
    } on DioException catch (e) { throw _client.mapError(e); }
  }

  Future<List<ApprovalHashEntryDto>> getApprovalHashes() async {
    try {
      final response = await _client.dio.get('/api/auth/approval-hashes');
      return ApprovalHashesResponseDto.fromJson(response.data as Map<String, dynamic>).hashes;
    } on DioException catch (e) { throw _client.mapError(e); }
  }

  Future<ServerAuthSessionDto> connectServer({required String email, required String password, required String supabaseUrl, required String publishableKey}) async {
    final authClient = Dio(BaseOptions(baseUrl: supabaseUrl));
    try {
      final response = await authClient.post('/auth/v1/token?grant_type=password', data: {'email': email, 'password': password}, options: Options(headers: {'apikey': publishableKey, 'content-type': 'application/json'}));
      final session = ServerAuthSessionDto.fromJson(response.data as Map<String, dynamic>);
      await _client.setServerAccessToken(session.accessToken);
      await _client.persistServerRefreshToken(session.refreshToken);
      return session;
    } on DioException catch (e) { throw _client.mapError(e); }
  }

  Future<ServerSignUpResult> signUpServer({required String email, required String password, required String supabaseUrl, required String publishableKey}) async {
    final authClient = Dio(BaseOptions(baseUrl: supabaseUrl));
    try {
      // Supabase Auth expects the email redirect to be supplied as the
      // signup request's redirect_to query parameter. Keeping it in the JSON
      // body is ignored by GoTrue, which makes Auth fall back to SITE_URL.
      final response = await authClient.post(
        '/auth/v1/signup',
        queryParameters: {'redirect_to': emailVerificationRedirect},
        data: {'email': email, 'password': password},
        options: Options(headers: {'apikey': publishableKey, 'content-type': 'application/json'}),
      );
      final data = Map<String, dynamic>.from(response.data as Map);
      final accessToken = data['access_token'] as String?;
      final refreshToken = data['refresh_token'] as String?;
      final user = data['user'] as Map<String, dynamic>?;
      if (accessToken != null && refreshToken != null && user != null) {
        final session = ServerAuthSessionDto(accessToken: accessToken, refreshToken: refreshToken, userId: user['id'] as String);
        await _client.setServerAccessToken(session.accessToken);
        await _client.persistServerRefreshToken(session.refreshToken);
        return ServerSignUpResult(session: session, emailConfirmed: user['email_confirmed_at'] != null);
      }
      return ServerSignUpResult(session: null, emailConfirmed: user?['email_confirmed_at'] != null);
    } on DioException catch (e) { throw _client.mapError(e); }
  }

  Future<void> acceptEmailVerificationTokens({required String accessToken, required String refreshToken}) async {
    if (accessToken.isEmpty || refreshToken.isEmpty) throw StateError('The verification link did not contain a complete session.');
    await _client.setServerAccessToken(accessToken);
    await _client.persistServerRefreshToken(refreshToken);
  }

  Future<Map<String, dynamic>> createCloudBusiness({required String name, required String functionBaseUrl, required String publishableKey, String currencyCode = 'NGN', String timezone = 'Africa/Lagos', String locationName = 'Main'}) async {
    try {
      final response = await Dio(BaseOptions(baseUrl: functionBaseUrl)).post('', data: {'action': 'create_business', 'name': name, 'currency_code': currencyCode, 'timezone': timezone, 'location_name': locationName}, options: Options(headers: {'apikey': publishableKey, 'Authorization': 'Bearer ${_client.serverAccessToken}', 'content-type': 'application/json'}));
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) { throw _client.mapError(e); }
  }

  Future<Map<String, dynamic>> registerCloudDevice({required String businessId, required String deviceClientId, required String deviceName, required String platform, required String appVersion, required String functionBaseUrl, required String publishableKey}) async {
    try {
      final response = await Dio(BaseOptions(baseUrl: functionBaseUrl)).post('', data: {'action': 'register_device', 'business_id': businessId, 'device_client_id': deviceClientId, 'device_name': deviceName, 'platform': platform, 'app_version': appVersion}, options: Options(headers: {'apikey': publishableKey, 'Authorization': 'Bearer ${_client.serverAccessToken}', 'content-type': 'application/json'}));
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) { throw _client.mapError(e); }
  }

  Future<ServerAuthSessionDto?> restoreServerSession({required String supabaseUrl, required String publishableKey}) async {
    final refreshToken = await _client.secureRefreshToken();
    if (refreshToken == null) return null;
    final authClient = Dio(BaseOptions(baseUrl: supabaseUrl));
    try {
      final response = await authClient.post('/auth/v1/token?grant_type=refresh_token', data: {'refresh_token': refreshToken}, options: Options(headers: {'apikey': publishableKey, 'content-type': 'application/json'}));
      final session = ServerAuthSessionDto.fromJson(response.data as Map<String, dynamic>);
      await _client.setServerAccessToken(session.accessToken);
      await _client.persistServerRefreshToken(session.refreshToken);
      return session;
    } on DioException {
      await _client.clearServerRefreshToken();
      _client.setAccessToken(null);
      return null;
    }
  }
}

class ServerAuthSessionDto {
  const ServerAuthSessionDto({required this.accessToken, required this.refreshToken, required this.userId});
  final String accessToken;
  final String refreshToken;
  final String userId;
  factory ServerAuthSessionDto.fromJson(Map<String, dynamic> json) => ServerAuthSessionDto(accessToken: json['access_token'] as String, refreshToken: json['refresh_token'] as String, userId: (json['user'] as Map<String, dynamic>)['id'] as String);
}

class ServerSignUpResult {
  const ServerSignUpResult({required this.session, required this.emailConfirmed});
  final ServerAuthSessionDto? session;
  final bool emailConfirmed;
}