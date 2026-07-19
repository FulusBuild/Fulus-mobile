import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import 'router.dart';

/// The root widget — per Architecture Section 1, main.dart stays thin
/// and delegates the actual app shell to this file. A ConsumerWidget
/// (Riverpod), not a plain StatelessWidget, since Architecture Section 2
/// establishes Riverpod as the app-wide default and this widget is where
/// theme-mode (light/dark, following Architecture Section 11 and Volume
/// 16's dark-mode tokens) will eventually be read from a provider rather
/// than hardcoded — not yet wired to a real theme-mode provider in this
/// phase (that provider doesn't exist yet), so ThemeMode.system is used
/// as the honest default for now: follow the device's own setting,
/// which is a real, correct behavior on its own, not a placeholder
/// standing in for something broken.
class BmsApp extends ConsumerWidget {
  const BmsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'BMS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
    );
  }
}
