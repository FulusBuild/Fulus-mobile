import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Owns the native auth callback link and turns it into an in-app route.
/// Supabase verification redirects to fulus://auth/callback#access_token=... .
/// Keeping link capture here means cold-start and warm-app verification use
/// the same path without exposing Supabase's hosted URL to the user.
class AuthDeepLinkGate extends ConsumerStatefulWidget {
  const AuthDeepLinkGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AuthDeepLinkGate> createState() => _AuthDeepLinkGateState();
}

class _AuthDeepLinkGateState extends ConsumerState<AuthDeepLinkGate> {
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _subscription;
  String? _lastHandled;

  @override
  void initState() {
    super.initState();
    _appLinks = AppLinks();
    _subscription = _appLinks.uriLinkStream.listen(_handle);
    unawaited(_captureInitialLink());
  }

  Future<void> _captureInitialLink() async {
    final uri = await _appLinks.getInitialLink();
    if (uri != null) _handle(uri);
  }

  void _handle(Uri uri) {
    if (!mounted ||
        uri.scheme != 'fulus' ||
        uri.host != 'auth' ||
        uri.path != '/callback') {
      return;
    }
    final key = uri.toString();
    if (_lastHandled == key) return;
    _lastHandled = key;
    context.go('/auth/callback', extra: uri);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
