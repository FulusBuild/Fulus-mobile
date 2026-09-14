import 'package:dio/dio.dart';

import '../../../core/errors/failure.dart';
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
    } on DioException catch (e) {
      final body = e.response?.data;
      if (body is Map && body['code'] == 'email_exists') {
        throw const BusinessRuleFailure(
          'An account with this email already exists. Sign in or resend the verification email.',
        );
      }
      throw _client.mapError(e);
    }
  }

  Future<void> resendSignupVerification({required String email, required String supabaseUrl, required String publishableKey}) async {
    final authClient = Dio(BaseOptions(baseUrl: supabaseUrl));
    try {
      await authClient.post(
        '/auth/v1/resend',
        queryParameters: {'type': 'signup'},
        data: {'email': email, 'options': {'email_redirect_to': emailVerificationRedirect}},
        options: Options(headers: {'apikey': publishableKey, 'content-type': 'application/json'}),
      );
    } on DioException catch (e) { throw _client.mapError(e); }
  }

  Future<void> acceptEmailVerificationTokens({required String accessToken, required String refreshToken}) async {
    if (accessToken.isEmpty || refreshToken.isEmpty) throw StateError('The verification link did not contain a complete session.');
    await _client.setServerAccessToken(accessToken);
    await _client.persistServerRefreshToken(refreshToken);
  }
}
