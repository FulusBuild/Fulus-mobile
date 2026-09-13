import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/design_tokens.dart';

/// Shared interaction rules for Phase 7. Keep feedback consistent across
/// high-frequency actions without coupling feature code to platform details.
class FulusHaptics {
  FulusHaptics._();

  static void selection() => HapticFeedback.selectionClick();

  static void confirm() => HapticFeedback.lightImpact();

  static void error() => HapticFeedback.heavyImpact();
}

/// A press target with a restrained scale response, semantic button role and
/// keyboard activation. Animation is removed when reduced motion is enabled.
class FulusPressable extends StatefulWidget {
  const FulusPressable({
    super.key,
    required this.child,
    required this.onPressed,
    this.semanticsLabel,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final String? semanticsLabel;

  @override
  State<FulusPressable> createState() => _FulusPressableState();
}

class _FulusPressableState extends State<FulusPressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onPressed == null || !mounted) return;
    setState(() => _pressed = value);
  }

  void _activate() {
    if (widget.onPressed == null) return;
    FulusHaptics.selection();
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final scale = reduceMotion || !_pressed ? 1.0 : 0.97;
    final content = AnimatedScale(
      scale: scale,
      duration: reduceMotion ? Duration.zero : AppMotion.fast,
      curve: Curves.easeOutCubic,
      child: widget.child,
    );

    return Semantics(
      button: true,
      enabled: widget.onPressed != null,
      label: widget.semanticsLabel,
      child: FocusableActionDetector(
        enabled: widget.onPressed != null,
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            _activate();
            return null;
          }),
        },
        onShowFocusHighlight: (focused) {
          if (!mounted || !focused) return;
          setState(() {});
        },
        child: MouseRegion(
          cursor: widget.onPressed == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed == null ? null : _activate,
            onTapDown: widget.onPressed == null ? null : (_) => _setPressed(true),
            onTapUp: widget.onPressed == null ? null : (_) => _setPressed(false),
            onTapCancel: widget.onPressed == null ? null : () => _setPressed(false),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Returns a compact horizontal inset that remains usable on narrow phones
/// while avoiding oversized gutters on tablets and desktop-sized windows.
double fulusHorizontalInset(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width < 360) return AppSpacing.md;
  if (width < 600) return AppSpacing.lg;
  return AppSpacing.xl;
}

/// Phase 7's single place for motion-aware durations. Feature code can keep
/// its intended duration while respecting system reduced-motion settings.
Duration fulusMotionDuration(BuildContext context, Duration duration) {
  return MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}
