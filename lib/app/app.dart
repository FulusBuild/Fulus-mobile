import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/email_verification_deep_link_handler.dart';
import '../core/theme/app_theme.dart';
import '../domain/entities/auth_user.dart';
import 'app_lock_gate.dart';
import 'restore_restart_gate.dart';
import 'auto_backup_gate.dart';
import 'providers.dart';
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
    // Session switching is an authorization boundary, not just a visual
    // rebuild. StatefulShellRoute keeps branch navigators alive, so the
    // router must re-run its permission redirect whenever the active
    // identity changes or a newly selected employee could inherit the
    // previous employee's protected route.
    ref.listen<AuthUser?>(sessionProvider, (previous, next) {
      if (previous?.id != next?.id || previous?.role != next?.role) {
        appRouter.refresh();
      }
    });

    return MaterialApp.router(
      title: 'Fulus',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
      builder: (context, child) => FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: RestoreRestartGate(
          child: AutoBackupGate(
            child: AppLockGate(child: child ?? const SizedBox.shrink()),
          ),
        ),
      ),
    );
  }
}
