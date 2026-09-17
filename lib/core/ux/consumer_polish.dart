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

/// A press target with restrained visual/tactile feedback, keyboard activation,
/// a visible focus treatment and a guaranteed 48dp hit area.
class FulusPressable extends StatefulWidget {
  const FulusPressable({super.key,required this.child,required this.onPressed,this.semanticsLabel});
  final Widget child; final VoidCallback? onPressed; final String? semanticsLabel;
  @override State<FulusPressable> createState()=>_FulusPressableState();
}
class _FulusPressableState extends State<FulusPressable>{
  bool _pressed=false; bool _focused=false;
  void _setPressed(bool value){if(widget.onPressed==null||!mounted)return;setState(()=>_pressed=value);}
  void _activate(){if(widget.onPressed==null)return;FulusHaptics.selection();widget.onPressed!();}
  @override Widget build(BuildContext context){final reduceMotion=MediaQuery.disableAnimationsOf(context);final scale=reduceMotion||!_pressed?1.0:.97;final primary=AppColors.primaryOf(context);final content=AnimatedScale(scale:scale,duration:reduceMotion?Duration.zero:AppMotion.fast,curve:Curves.easeOutCubic,child:widget.child);return Semantics(button:true,enabled:widget.onPressed!=null,label:widget.semanticsLabel,child:FocusableActionDetector(enabled:widget.onPressed!=null,shortcuts:const<ShortcutActivator,Intent>{SingleActivator(LogicalKeyboardKey.enter):ActivateIntent(),SingleActivator(LogicalKeyboardKey.space):ActivateIntent()},actions:<Type,Action<Intent>>{ActivateIntent:CallbackAction<ActivateIntent>(onInvoke:(_){_activate();return null;})},onShowFocusHighlight:(focused){if(!mounted)return;setState(()=>_focused=focused);},child:MouseRegion(cursor:widget.onPressed==null?SystemMouseCursors.basic:SystemMouseCursors.click,child:GestureDetector(behavior:HitTestBehavior.opaque,onTap:widget.onPressed==null?null:_activate,onTapDown:widget.onPressed==null?null:(_)=>_setPressed(true),onTapUp:widget.onPressed==null?null:(_)=>_setPressed(false),onTapCancel:widget.onPressed==null?null:()=>_setPressed(false),child:ConstrainedBox(constraints:const BoxConstraints(minWidth:AppTouchTarget.minimum,minHeight:AppTouchTarget.minimum),child:AnimatedContainer(duration:reduceMotion?Duration.zero:AppMotion.fast,decoration:_focused?BoxDecoration(borderRadius:BorderRadius.circular(AppRadius.sm),border:Border.all(color:primary,width:2)):null,child:content))))));}
}

/// Width-based layout primitives. Layout adapts to the available app window;
/// it does not globally scale typography, touch targets, or controls.
class FulusLayout {
  FulusLayout._();

  static const maxContentWidth = 1120.0;
  static const tabletBreakpoint = 600.0;
  static const wideBreakpoint = 840.0;
  static const largeBreakpoint = 1200.0;

  static double width(BuildContext context) => MediaQuery.sizeOf(context).width;
  static bool isTablet(BuildContext context) => width(context) >= tabletBreakpoint;
  static bool isWide(BuildContext context) => width(context) >= wideBreakpoint;

  /// Shared gutters: compact phones stay efficient; larger windows gain
  /// breathing room without allowing content to drift to the screen edges.
  static double horizontalInset(BuildContext context) {
    final value = width(context);
    if (value < 360) return AppSpacing.md;
    if (value < tabletBreakpoint) return AppSpacing.lg;
    if (value < largeBreakpoint) return AppSpacing.xl;
    return AppSpacing.xxl;
  }

  /// Calculates columns from the available width and a minimum comfortable
  /// tile width, keeping repeated cards stable while density adapts.
  static int columns(double availableWidth, {double minTileWidth = 160, int maxColumns = 4}) {
    if (!availableWidth.isFinite || availableWidth <= 0) return 1;
    return (availableWidth / minTileWidth).floor().clamp(1, maxColumns);
  }
}

double fulusHorizontalInset(BuildContext context) => FulusLayout.horizontalInset(context);
Duration fulusMotionDuration(BuildContext context,Duration duration)=>MediaQuery.disableAnimationsOf(context)?Duration.zero:duration;
