import 'package:flutter/material.dart';

/// Design tokens: color, typography, spacing, motion. No hex color or
/// raw spacing/duration number should appear inline anywhere else in
/// the codebase — UI code references these names instead.
class AppColors {
  AppColors._();

  // Primary doubles as the success color (primary buttons, the Sell
  // action, positive/synced states) — there is no separate "success"
  // token.
  static const primary = Color(0xFF0E6B5C);

  static const warning = Color(0xFFD97706);
  static const error = Color(0xFFB3261E);
  // info is treated as a peer of warning/error: same flat semantic-alias
  // treatment, own tint ramp, own dark variant.
  static const info = Color(0xFF2E629E);

  static const textPrimaryLight = Color(0xFF1A1A1A);
  static const textSecondaryLight = Color(0xFF6B6B6B);
  static const borderLight = Color(0xFFE6E6E6);

  static const backgroundLight = Color(0xFFFAFAFA);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceAltLight = Color(0xFFF3F3F3);

  // Dark mode isn't light mode inverted — surfaces lift slightly above
  // pure black instead of true black-on-black.
  static const backgroundDark = Color(0xFF121212);
  static const surfaceDark = Color(0xFF1E1E1E);
  static const surfaceAltDark = Color(0xFF292929);
  static const borderDark = Color(0xFF333333);

  static const darkWarning = Color(0xFFE69E4C);
  static const darkWarningOn = Color(0xFF1A1A1A);
  static const darkError = Color(0xFFE27A74);
  static const darkErrorOn = Color(0xFF2A0A08);
  static const darkPrimary = Color(0xFF41C8B2);
  static const darkPrimaryStrong = Color(0xFF6BD9C6);
  static const darkOnPrimary = Color(0xFF0A2420);
  static const darkInfo = Color(0xFF699BD3);
  static const darkTextPrimary = Color(0xFFF0F0F0);
  static const darkTextSecondary = Color(0xFFADADAD);

  // Tint ramps for call sites needing something between a flat semantic
  // color and a hand-picked hex: chip fills, pressed/hover states,
  // subtle backgrounds.
  static const primary50 = Color(0xFFEEF9F7);
  static const primary100 = Color(0xFFD4F2ED);
  static const primary200 = Color(0xFFA1E8DC);
  static const primary300 = Color(0xFF5EDEC9);
  static const primary400 = Color(0xFF1FBDA3);
  static const primary500 = primary; // alias — same value as AppColors.primary
  static const primary600 = Color(0xFF0A594C);
  static const primary700 = Color(0xFF08493E);
  static const primary800 = Color(0xFF053830);
  static const primary900 = Color(0xFF032721);

  static const secondary50 = Color(0xFFFAF7ED);
  static const secondary100 = Color(0xFFF3ECD3);
  static const secondary200 = Color(0xFFE6D6A2);
  static const secondary300 = Color(0xFFD8C06E);
  static const secondary400 = Color(0xFFCBA93A);
  static const secondary500 = Color(0xFFA1862B);
  static const secondary600 = Color(0xFF876F22);
  static const secondary700 = Color(0xFF705C1A);
  static const secondary800 = Color(0xFF584813);
  static const secondary900 = Color(0xFF3F340D);

  static const info50 = Color(0xFFEFF4FB);
  static const info100 = Color(0xFFD6E4F5);
  static const info200 = Color(0xFFADCAEB);
  static const info300 = Color(0xFF7EAADD);
  static const info400 = Color(0xFF4C88CD);
  static const info500 = info; // alias — same value as AppColors.info
  static const info600 = Color(0xFF245389);
  static const info700 = Color(0xFF1D4572);
  static const info800 = Color(0xFF15365B);
  static const info900 = Color(0xFF0F2743);

  static const neutral0 = Color(0xFFFFFFFF);
  static const neutral50 = Color(0xFFFAFAFA);
  static const neutral100 = Color(0xFFF3F3F3);
  static const neutral200 = Color(0xFFE6E6E6);
  static const neutral300 = Color(0xFFC9C9C9);
  static const neutral400 = Color(0xFFA8A8A8);
  static const neutral500 = Color(0xFF8A8A8A);
  static const neutral600 = Color(0xFF6B6B6B);
  static const neutral700 = Color(0xFF4C4C4C);
  static const neutral800 = Color(0xFF2F2F2F);
  static const neutral900 = Color(0xFF1A1A1A);

  // --- Brightness-aware accessors ---------------------------------
  // Every screen shipped before this foundation phase (Home, Employees,
  // Reports, Backup) reads the flat Light-suffixed constants above
  // directly and ignores brightness entirely — real on a device set to
  // system dark mode, since ThemeMode.system is wired in app.dart
  // (app/app.dart), but out of scope for this phase to fix (those are
  // feature-owned files). These accessors exist so the shared widgets
  // built in this same phase don't repeat that gap: a component calls
  // `AppColors.surfaceOf(context)` once and gets the right token for
  // whichever theme is active, rather than hand-rolling a
  // `Theme.of(context).brightness == Brightness.dark` check at every
  // call site. Purely additive — no existing call site is touched or
  // required to migrate.
  static bool isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;

  static Color primaryOf(BuildContext context) => isDark(context) ? darkPrimary : primary;
  static Color onPrimaryOf(BuildContext context) => isDark(context) ? darkOnPrimary : neutral0;
  static Color warningOf(BuildContext context) => isDark(context) ? darkWarning : warning;
  static Color warningOnOf(BuildContext context) => isDark(context) ? darkWarningOn : textPrimaryLight;
  static Color errorOf(BuildContext context) => isDark(context) ? darkError : error;
  static Color errorOnOf(BuildContext context) => isDark(context) ? darkErrorOn : neutral0;
  static Color infoOf(BuildContext context) => isDark(context) ? darkInfo : info;
  static Color backgroundOf(BuildContext context) => isDark(context) ? backgroundDark : backgroundLight;
  static Color surfaceOf(BuildContext context) => isDark(context) ? surfaceDark : surfaceLight;
  static Color surfaceAltOf(BuildContext context) => isDark(context) ? surfaceAltDark : surfaceAltLight;
  static Color borderOf(BuildContext context) => isDark(context) ? borderDark : borderLight;
  static Color textPrimaryOf(BuildContext context) => isDark(context) ? darkTextPrimary : textPrimaryLight;
  static Color textSecondaryOf(BuildContext context) => isDark(context) ? darkTextSecondary : textSecondaryLight;

  /// The "Primary/50 fill" selected-state tint used by Chips and the
  /// Dropdown/Select's selected row. primary50 is a light-surface tint
  /// with no dark-mode counterpart, so dark mode instead applies
  /// AppOpacity.badgeTintDark (0.14) over darkPrimary — the two real
  /// per-theme values collapsed into one accessor.
  static Color selectedTintOf(BuildContext context) =>
      isDark(context) ? darkPrimary.withValues(alpha: AppOpacity.badgeTintDark) : primary50;
}

class AppTypography {
  AppTypography._();

  // Roboto is not set explicitly as a fontFamily anywhere in this file:
  // Flutter's Material theme already defaults to the platform's system
  // font on Android without an explicit override, so setting one here
  // would be redundant at best and a real risk of silently diverging
  // from "system font" if Roboto ever isn't the Android default.

  static const display = TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.bold,
    height: 1.15,
    letterSpacing: -0.5,
  );

  static const title = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.3,
  );

  static const heading = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600, // Semibold
    height: 1.25,
  );

  static const subheading = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  // body's larger sibling, for lead paragraphs and empty-state copy
  // where 16sp reads slightly cramped.
  static const bodyLarge = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.normal,
    height: 1.55,
  );

  // 16sp as the body minimum is deliberate: smaller is common in this
  // app category, but not appropriate for the low-vision and
  // low-literacy accessibility bar this product targets. Not a default
  // Material body size either (Flutter's Typography.material2021
  // bodyMedium is 14sp) — a specific product requirement, named here
  // explicitly rather than left to Flutter's default.
  static const body = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.normal,
    height: 1.6,
  );

  static const caption = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    height: 1.5,
  );

  // Small, weighted, wide-tracked — chip/tag text and section eyebrows,
  // distinct from caption's body-adjacent use (e.g. helper text under a
  // field).
  static const label = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.4,
    letterSpacing: 0.6,
  );

  // 4 existing call sites reference AppTypography.buttonLabel already;
  // kept this name rather than renaming for a purely cosmetic sync.
  static const buttonLabel = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0.1,
  );
}

/// A 4dp base unit, scaling as 4/8/12/16/24/32/48. Named constants
/// rather than a raw list, so a call site reads as `AppSpacing.md`
/// (intent) rather than `spacingScale[3]` (an index that says nothing
/// about why that value was chosen at that call site).
class AppSpacing {
  AppSpacing._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;
}

/// Corner radius scale.
class AppRadius {
  AppRadius._();

  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 20.0;
  static const pill = 999.0;
}

/// Two-level elevation system — deliberately not a 0–5 Material scale.
/// This app only ever needs "resting" (cards, list rows) and "lifted"
/// (dialogs, sheets, the elevated Sell button, Home hero). A third
/// level was never designed because nothing in the product sits at an
/// in-between depth; add one only if a real screen needs it, not
/// speculatively.
class AppElevation {
  AppElevation._();

  static const cardLight = [
    BoxShadow(offset: Offset(0.0, 1.0), blurRadius: 2.0, color: Color(0x0A141414)),
    BoxShadow(offset: Offset(0.0, 4.0), blurRadius: 16.0, color: Color(0x0F141414)),
  ];
  static const liftLight = [
    BoxShadow(offset: Offset(0.0, 10.0), blurRadius: 32.0, color: Color(0x2E141414)),
    BoxShadow(offset: Offset(0.0, 3.0), blurRadius: 10.0, color: Color(0x1A141414)),
  ];
  static const cardDark = [
    BoxShadow(offset: Offset(0.0, 1.0), blurRadius: 2.0, color: Color(0x4C000000)),
    BoxShadow(offset: Offset(0.0, 4.0), blurRadius: 20.0, color: Color(0x73000000)),
  ];
  static const liftDark = [
    BoxShadow(offset: Offset(0.0, 14.0), blurRadius: 36.0, color: Color(0x99000000)),
    BoxShadow(offset: Offset(0.0, 3.0), blurRadius: 12.0, color: Color(0x66000000)),
  ];

  /// Same rationale as [AppColors.surfaceOf] — lets a shared widget ask
  /// for "the card shadow" once, brightness-correct, instead of
  /// branching at the call site.
  static List<BoxShadow> cardOf(BuildContext context) =>
      AppColors.isDark(context) ? cardDark : cardLight;
  static List<BoxShadow> liftOf(BuildContext context) =>
      AppColors.isDark(context) ? liftDark : liftLight;
}

/// Named opacity values, so a dimmed row or a scrim references a name
/// instead of a new inline literal at every call site.
class AppOpacity {
  AppOpacity._();

  /// Illustration grounding ellipse only.
  static const groundShadow = 0.06;
  /// Dark-mode approval-note backgrounds.
  static const subtleTintDark = 0.08;
  /// Dark-mode selected chip/tag fills (12–16% depending on tag; 0.14 is the default).
  static const badgeTintDark = 0.14;
  /// Dimmed payment rows, unavailable options — the standard "unavailable" treatment.
  static const disabled = 0.4;
  /// Dialog / bottom sheet backdrop.
  static const scrim = 0.45;
}

/// Minimum touch target: 48×48dp, everywhere, no exceptions. Not folded
/// into AppSpacing.xxxl even though the numeric value is identical
/// (48.0), because the two mean different things at a call site:
/// AppSpacing.xxxl is "the largest step on the spacing scale",
/// AppTouchTarget.minimum is "the accessibility floor for anything
/// tappable" — conflating them would make a future spacing change
/// silently also change the touch-target floor, or vice versa.
class AppTouchTarget {
  AppTouchTarget._();

  static const minimum = 48.0;
}

/// Motion: 150-250ms standard, 300ms ceiling. Matches this app's own
/// "step-to-step transitions under 300ms" performance target exactly —
/// the product spec and the performance target are the same number, not
/// a coincidence worth losing track of.
class AppMotion {
  AppMotion._();

  static const fast = Duration(milliseconds: 120);
  static const standard = Duration(milliseconds: 200);
  static const ceiling = Duration(milliseconds: 300);

  // Built with Cubic() directly rather than a named Curves.* constant,
  // so the Flutter easing is the exact bezier this design system uses
  // (--ease-standard / --ease-decelerate), not merely a visually-similar
  // named curve.
  static const curveStandard = Cubic(0.4, 0.0, 0.2, 1.0); // cubic-bezier(0.4,0,0.2,1)
  static const curveDecelerate = Cubic(0.0, 0.0, 0.2, 1.0); // cubic-bezier(0,0,0.2,1)
}

/// Icon sizing scale.
class AppIconSize {
  AppIconSize._();

  static const dense = 16.0;
  static const compact = 20.0;
  static const base = 24.0;
  static const emphasis = 32.0;
  static const hero = 48.0;
  static const strokeWidth = 2.0;
}

/// Minimum contrast: 4.5:1 for all body text, in both themes. Verified
/// directly: computed the real WCAG relative-luminance contrast ratio
/// for every light-theme text/background pairing this token set
/// produces. Text Primary (#1A1A1A) against Background Light (#FAFAFA)
/// is 16.67:1; against Surface Light (#FFFFFF) is 17.40:1. Text
/// Secondary (#6B6B6B) — the tighter case, as expected for a
/// deliberately muted color — is 5.11:1 against Background Light and
/// 5.33:1 against Surface Light. All four clear the 4.5:1 floor with
/// real margin, not marginally.
///
/// Dark-theme pairings, computed the same way: Text Primary Dark
/// (#F0F0F0) against Background Dark (#121212) is ~16.4:1; against
/// Surface Dark (#1E1E1E) is ~14.6:1. Text Secondary Dark (#ADADAD) —
/// again the tighter case — is ~8.4:1 against Background Dark and
/// ~7.4:1 against Surface Dark. All four clear the floor with more
/// margin than their light-theme counterparts, not less.
const double kMinimumContrastRatio = 4.5;

/// A small, additive set of hero-surface gradients. This app only has
/// two elevation levels and deliberately avoids inventing a third "just
/// because" — the same discipline applies here: not a general-purpose
/// gradient library, only the two surfaces actually needed (Home's
/// hero, and the sale-success celebration moment), each derived from
/// tokens that already exist rather than new hand-picked hex values.
/// Kept as a diagonal 2-stop primary ramp — subtle enough to still read
/// as "the primary color" at a glance, not a decorative rainbow.
class AppGradients {
  AppGradients._();

  static LinearGradient heroOf(BuildContext context) {
    final isDark = AppColors.isDark(context);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? [AppColors.primary700, AppColors.darkPrimaryStrong.withValues(alpha: 0.55)]
          : [AppColors.primary600, AppColors.primary],
    );
  }

  static LinearGradient successOf(BuildContext context) {
    final isDark = AppColors.isDark(context);
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: isDark
          ? [AppColors.primary700, AppColors.surfaceDark]
          : [AppColors.primary50, AppColors.surfaceLight],
    );
  }
}
