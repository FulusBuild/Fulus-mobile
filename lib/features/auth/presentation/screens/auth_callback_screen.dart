import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../shared/widgets/widgets.dart';

class AuthCallbackScreen extends ConsumerStatefulWidget {
  const AuthCallbackScreen({required this.uri, super.key});

  final Uri uri;

  @override
  ConsumerState<AuthCallbackScreen> createState() => _AuthCallbackScreenState();
}

class _AuthCallbackScreenState extends ConsumerState<AuthCallbackScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _complete();
  }

  Future<void> _complete() async {
    try {
      final session = await ref.read(authApiProvider).restoreServerSessionFromCallback(
        uri: widget.uri,
        supabaseUrl: SupabaseConfig.url,
        publishableKey: SupabaseConfig.publishableKey,
      );
      if (session == null) throw StateError('Email verification did not create a valid cloud session.');
      final storage = ref.read(secureStorageProvider);
      final businessName = await storage.getPendingCloudBusinessName();
      await storage.deletePendingCloudBusinessName();
      if (!mounted) return;
      context.goNamed('moreSettingsCloud', extra: businessName);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString().replaceFirst('Bad state: ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error == null) {
      return const FulusScreen(
        title: 'Email verified',
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return FulusScreen(
      title: 'Email verification',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_error!),
          const SizedBox(height: 16),
          FulusButton(
            label: 'Back to cloud setup',
            onPressed: () => context.goNamed('moreSettingsCloud'),
          ),
        ],
      ),
    );
  }
}
