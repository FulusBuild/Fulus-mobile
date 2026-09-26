import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/home/presentation/screens/home_screen.dart';

/// Web-only visual QA entrypoint.
///
/// This intentionally stays separate from [main.dart]: the production
/// bootstrap currently depends on Android/local-device services and is not
/// a web runtime. The web target is therefore a browser-based visual QA
/// surface, not a second production platform.
void main() {
  runApp(const FulusWebVisualQaApp());
}

class FulusWebVisualQaApp extends StatelessWidget {
  const FulusWebVisualQaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fulus Visual QA',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const _WebVisualQaUnavailable(),
    );
  }
}

class _WebVisualQaUnavailable extends StatelessWidget {
  const _WebVisualQaUnavailable();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Fulus Web Visual QA target is enabled. '
              'The production runtime uses device-local services and is '
              'currently Android-only; screen fixtures will be wired here '
              'before browser visual assertions are enabled.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
