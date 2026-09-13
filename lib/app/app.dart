import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/email_verification_deep_link_handler.dart';
import '../core/theme/app_theme.dart';
import 'app_lock_gate.dart';
import 'auto_backup_gate.dart';
import 'router.dart';

class FulusApp extends ConsumerStatefulWidget {
  const FulusApp({super.key});

  @override
  ConsumerState<FulusApp> createState() => _FulusAppState();
}

class _FulusAppState extends ConsumerState<FulusApp> {
  late final EmailVerificationDeepLinkHandler _emailVerificationHandler;

  @override
  void initState() {
    super.initState();
    _emailVerificationHandler = EmailVerificationDeepLinkHandler(ref.container);
    unawaited(_emailVerificationHandler.start());
  }

  @override
  void dispose() {
    unawaited(_emailVerificationHandler.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Fulus',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
      builder: (context, child) => FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: AutoBackupGate(
          child: AppLockGate(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}
