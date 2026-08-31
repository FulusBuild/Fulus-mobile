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
        // Bug fix — AppLockScreen uses a real TextField (via
        // FulusTextField) for PIN entry, and a TextField's EditableText
        // needs an Overlay ancestor for its SelectionOverlay/IME
        // machinery — not optional decoration, a hard requirement. This
        // Stack sits outside MaterialApp.router's own Navigator/Overlay
        // by construction (that's the whole point of using `builder:`
        // here — see this class's own doc comment), so previously there
        // was none. Symptom: enter a wrong PIN, and the field won't
        // accept new input or let you clear it — Android's IME keeps
        // sending updateEditingState calls into an EditableText whose
        // Overlay lookup fails, corrupting its input connection until
        // the app is fully restarted. Wrapping just this branch in its
        // own [Overlay] gives it a real one without needing a second
        // Navigator.
        if (_locked)
          Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (context) => AppLockScreen(onUnlocked: () => setState(() => _locked = false)),
              ),
            ],
          ),
      ],
    );
  }
}
