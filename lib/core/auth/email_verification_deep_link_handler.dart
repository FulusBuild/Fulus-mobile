import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

/// Captures Supabase's post-verification custom-scheme callback and persists
/// the returned session before the normal app router is evaluated again.
class EmailVerificationDeepLinkHandler {
  EmailVerificationDeepLinkHandler(this._container);

  final ProviderContainer _container;
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;

  Future<void> start() async {
    _subscription = _appLinks.uriLinkStream.listen(_handle);
    final initial = await _appLinks.getInitialLink();
    if (initial != null) await _handle(initial);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _handle(Uri uri) async {
    if (uri.scheme != 'fulus' || uri.host != 'auth' || uri.path != '/callback') return;

    final errorCode = uri.fragment.isNotEmpty ? _fragmentValue(uri.fragment, 'error_code') : null;
    if (errorCode != null) return;

    final accessToken = _fragmentValue(uri.fragment, 'access_token');
    final refreshToken = _fragmentValue(uri.fragment, 'refresh_token');
    if (accessToken == null || refreshToken == null) return;

    try {
      await _container.read(authApiProvider).acceptEmailVerificationTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
          );
    } catch (_) {
      // The normal cloud connection screen remains available if a malformed
      // callback arrives; never make local-first startup depend on this hop.
    }
  }

  String? _fragmentValue(String fragment, String key) {
    for (final part in fragment.split('&')) {
      final separator = part.indexOf('=');
      if (separator <= 0) continue;
      final name = Uri.decodeComponent(part.substring(0, separator));
      if (name != key) continue;
      return Uri.decodeComponent(part.substring(separator + 1));
    }
    return null;
  }
}
