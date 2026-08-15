import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/presentation/screens/app_lock_screen.dart';
import 'providers.dart';

/// Wraps [MaterialApp.router]'s entire navigated content via its own
/// `builder` hook — the right tool for something that needs to overlay
/// regardless of go_router's current route, rather than a route of its
/// own that would have to be pushed/popped around whatever's already on
/// the navigation stack.
///
/// Locks on `paused`, not `resumed` — so the OS's own recent-apps
/// thumbnail captures the locked screen, not whatever was on-screen
/// (a sale in progress, a customer's balance) the moment the app was
/// backgrounded. Also checks on cold start, so force-quitting the app
/// isn't a way around the lock.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> with WidgetsBindingObserver {
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkLock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkLock() async {
    final config = await ref.read(appLockConfigProvider.future);
    if (await config.isActive() && mounted) {
      setState(() => _locked = true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _checkLock();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_locked) AppLockScreen(onUnlocked: () => setState(() => _locked = false)),
      ],
    );
  }
}
