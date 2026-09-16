import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';

/// Verifies the public Supabase signup contract without requiring an email
/// inbox. A successful response may either contain a session or a newly
/// created user awaiting email confirmation, depending on project settings.
Future<void> main() async {
  final supabaseUrl = _required('SUPABASE_URL');
  final publishableKey = _required('SUPABASE_PUBLISHABLE_KEY');
  final suffix =
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(10000)}';
  final email = 'fulus-ci-$suffix@example.invalid';
  final password = 'FulusCI-${Random().nextInt(100000000)}!aA';

  final dio = Dio(BaseOptions(
    baseUrl: supabaseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    headers: {
      'apikey': publishableKey,
      'content-type': 'application/json',
    },
    validateStatus: (_) => true,
  ));

  final response = await dio.post(
    '/auth/v1/signup',
    queryParameters: {'redirect_to': 'fulus://auth/callback'},
    data: {'email': email, 'password': password},
  );

  final status = response.statusCode ?? 0;
  if (status < 200 || status >= 300) {
    throw StateError(
      'Account creation failed with HTTP $status: ${response.data}',
    );
  }

  final body = response.data is Map
      ? Map<String, dynamic>.from(response.data as Map)
      : <String, dynamic>{};
  final user = body['user'] is Map
      ? Map<String, dynamic>.from(body['user'] as Map)
      : null;
  final accessToken = body['access_token'];

  if (accessToken is String && accessToken.isNotEmpty && user != null) {
    stdout.writeln('PASS: account creation returned an authenticated session.');
    stdout.writeln('PASS: signup contract');
    return;
  }

  if (user != null && user['id'] is String) {
    stdout.writeln(
      'PASS: account creation accepted; session is pending email confirmation.',
    );
    stdout.writeln('PASS: signup contract');
    return;
  }

  throw StateError(
    'Signup returned neither a session nor a user record: $body',
  );
}

String _required(String name) {
  final value = Platform.environment[name];
  if (value == null || value.isEmpty) {
    throw StateError('$name is required.');
  }
  return value;
}
