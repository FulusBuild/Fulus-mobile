import 'package:flutter/material.dart';

/// Every value below is copied directly from Volume 16 (Mobile Design
/// System) of the Fulus Mobile Product Design Bible's own "Design Tokens:
/// The Reference Table" — re-read from the source document immediately
/// before writing this file, not recalled from an earlier pass through
/// it weeks prior. Per Architecture Section 1: "Volume 16 tokens: color,
/// typography, spacing — as Dart constants, not hardcoded [inline
/// throughout the UI]." This file IS that constant set; nowhere else in
/// the codebase should a hex color or a raw spacing number appear
/// inline — every UI file references these names instead.
class AppColors {
  AppColors._();

  // "Primary doubles as the success color rather than introducing a
  // second green" — Volume 16, Color System. Used for primary buttons,
  // the elevated Sell action, and positive/synced states, per the
  // Bible's own stated reuse — there is no separate "success" token.
  static const primary = Color(0xFF0E6B5C);

  static const warning = Color(0xFFD97706);
  static const error = Color(0xFFB3261E);
  // No standalone "info" concept existed in this file before — the
  // Visual Design Bible treats it as a full peer of warning/error (its
  // own 50–900 ramp, its own dark variant), so it gets the same flat
  // semantic alias treatment those two already have.
  static const info = Color(0xFF2E629E);

  static const textPrimaryLight = Color(0xFF1A1A1A);
  static const textSecondaryLight = Color(0xFF6B6B6B);
  static const borderLight = Color(0xFFE6E6E6);

  static const backgroundLight = Color(0xFFFAFAFA);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceAltLight = Color(0xFFF3F3F3);

  // "Dark mode isn't light mode inverted. Surfaces lift slightly above
  // pure black... rather than true black-on-black" — Volume 16, Dark
  // Mode & Light Mode.
  static const backgroundDark = Color(0xFF121212);
  static const surfaceDark = Color(0xFF1E1E1E);
  static const surfaceAltDark = Color(0xFF292929);
  static const borderDark = Color(0xFF333333);

  // Volume 16 states colors "desaturate a touch in dark mode" but gives
  // no exact desaturated hex values in its own prose — only the
  // light-mode values and that qualitative direction. The Visual Design
  // Bible (10-Design-Tokens, not Volume 16 itself) since worked out real
  // values for this; sourced from there rather than invented here.
  static const darkWarning = Color(0xFFE69E4C);
  static const darkWarningOn = Color(0xFF1A1A1A);
  static const darkError = Color(0xFFE27A74);
  static const darkErrorOn = Color(0xFF2A0A08);
  static const darkPrimary = Color(0xFF41C8B2);
  static const darkPrimaryStrong = Color(0xFF6BD9C6);
  static const darkOnPrimary = Color(0xFF0A2420);
  static const darkInfo = Color(0xFF699BD3);
  // Text — sourced from the Visual Design Bible's 10-Design-Tokens.dart
  // (darkTextPrimary/darkTextSecondary), the same source as the
  // desaturated semantic colors above. This file previously had no
  // dark-mode text values at all — AppTheme.dark fell back to
  // Colors.white/white70 as an honest placeholder rather than inventing
  // a hex value Volume 16 never stated. The Bible has since worked out
  // real values, so that placeholder is retired below.
  static const darkTextPrimary = Color(0xFFF0F0F0);
  static const darkTextSecondary = Color(0xFFADADAD);
  // Foundation phase (shared components + theme reconciliation):
  // AppTheme.dark now consumes every dark-mode token above — see
  // app_theme.dart. The "does NOT consume these yet" gap this comment
  // used to flag is closed.

  // Full tint ramps, for call sites needing something between a flat
  // semantic color and a hand-picked hex (chip fills, pressed/hover
  // states, subtle tints). Neither Volume 16 nor this file exposed
  // these before; sourced from the Visual Design Bible's own ramps,
  // which is the only place they're defined.
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

  /// The "Primary/50 fill" selected-state tint used by Chips (5.2) and
  /// the Dropdown/Select's selected row (5.13). primary50 is a
  /// light-surface tint with no dark-mode counterpart defined anywhere
  /// in the Bible, so dark mode instead applies AppOpacity.badgeTintDark
  /// (0.14) over darkPrimary — that opacity value is exactly what the
  /// Bible itself specifies for "dark-mode selected chip/tag fills," so
  /// this isn't an invented number, just the two real per-theme values
  /// collapsed into one accessor.
  static Color selectedTintOf(BuildContext context) =>
      isDark(context) ? darkPrimary.withOpacity(AppOpacity.badgeTintDark) : primary50;
}

class AppTypography {
  AppTypography._();

  // Sizes and weights per Volume 16's Typography table exactly. Roboto
  // is not set explicitly as a fontFamily anywhere in this file — Volume
  // 16 states "The system font (Roboto on Android), not a custom
  // typeface", and Flutter's Material theme already defaults to the
  // platform's system font on Android without needing an explicit
  // fontFamily override, so setting one here would be redundant at best
  // and a real risk of silently diverging from "system font" if Roboto
  // ever isn't the system default on some future Android version.

  static const display = TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.bold,
    height: 1.15,
    letterSpacing: -0.5,
  );

  // New — the Bible's scale has a step between display and heading that
  // this file didn't have yet.
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

  // New.
  static const subheading = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  // New — body's larger sibling; the Bible uses this for lead paragraphs
  // and empty-state copy where 16sp reads slightly cramped.
  static const bodyLarge = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.normal,
    height: 1.55,
  );

  // "16sp as the body minimum is deliberate — smaller is common in this
  // category, but not appropriate for the low-vision and low-literacy
  // accessibility bar set in Volume 1." This is not a default Material
  // body size (Flutter's own Typography.material2021 bodyMedium is
  // 14sp) — it's a specific, deliberate product requirement, which is
  // exactly why it's named here explicitly rather than left to Flutter's
  // own default and assumed to already be correct.
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

  // New — small, weighted, wide-tracked; the Bible uses this for chip/
  // tag text and section eyebrows, distinct from caption's body-adjacent
  // use (e.g. helper text under a field).
  static const label = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.4,
    letterSpacing: 0.6,
  );

  // Named buttonLabel here, "button" in the Bible's own export — kept
  // this file's existing name rather than renaming (4 existing call
  // sites reference AppTypography.buttonLabel already; renaming is a
  // pure cosmetic sync with zero functional benefit for the churn).
  static const buttonLabel = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0.1,
  );
}

/// "A 4dp base unit, scaling as: 4, 8, 12, 16, 24, 32, 48." — Volume 16,
/// Spacing & Layout. Named constants rather than a raw list, so a call
/// site reads as `AppSpacing.md` (intent) rather than `spacingScale[3]`
/// (an index into a list, which says nothing about why that value was
/// chosen at that call site).
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

/// Corner radius scale. Didn't exist as named constants anywhere before
/// this — call sites presumably hardcoded BorderRadius values inline.
/// Sourced from the Visual Design Bible's own radius scale.
class AppRadius {
  AppRadius._();

  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 20.0;
  static const pill = 999.0;
}

/// Two-level elevation system — deliberately not a 0–5 Material scale.
/// Per the Visual Design Bible: "Fulus only ever needs 'resting' (cards,
/// list rows) and 'lifted' (dialogs, sheets, the elevated Sell button,
/// Home hero). A third level was never designed because nothing in the
/// product sits at an in-between depth; add one only if a real screen
/// needs it, not speculatively."
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
/// instead of a new inline literal at every call site — per the Bible,
/// this table existed in prose before but was never exposed as reusable
/// values in any format.
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

/// "Minimum touch target: 48×48dp, everywhere, no exceptions." — Volume
/// 16, Accessibility. Not folded into AppSpacing.xxxl even though the
/// numeric value is identical (48.0), because the two mean different
/// things at a call site: AppSpacing.xxxl is "the largest step on the
/// spacing scale", AppTouchTarget.minimum is "the accessibility floor
/// for anything tappable" — conflating them would make a future spacing
/// change silently also change the touch-target floor, or vice versa.
class AppTouchTarget {
  AppTouchTarget._();

  static const minimum = 48.0;
}

/// "Motion 150–250ms standard, 300ms ceiling (Volume 15)." — Volume 16's
/// own reference table, cross-referencing Volume 15. Matches Architecture
/// Section 12's own "step-to-step transitions under 300ms" performance
/// target exactly — the product spec and the performance target are the
/// same number, not a coincidence worth losing track of.
class AppMotion {
  AppMotion._();

  static const fast = Duration(milliseconds: 120);
  static const standard = Duration(milliseconds: 200);
  static const ceiling = Duration(milliseconds: 300); // Bible calls this "slow" — same 300ms value

  // Built with Cubic() directly rather than a named Curves.* constant,
  // so the Flutter easing is the exact same bezier as --ease-standard /
  // --ease-decelerate in the Bible's CSS, not merely a visually-similar
  // named curve.
  static const curveStandard = Cubic(0.4, 0.0, 0.2, 1.0); // cubic-bezier(0.4,0,0.2,1)
  static const curveDecelerate = Cubic(0.0, 0.0, 0.2, 1.0); // cubic-bezier(0,0,0.2,1)
}

/// Icon sizing scale. Didn't exist as named constants before this.
class AppIconSize {
  AppIconSize._();

  static const dense = 16.0;
  static const compact = 20.0;
  static const base = 24.0;
  static const emphasis = 32.0;
  static const hero = 48.0;
  static const strokeWidth = 2.0;
}

/// "Minimum contrast: 4.5:1 for all body text, in both themes." — Volume
/// 16, Accessibility. Verified directly, not just referenced: computed
/// the real WCAG relative-luminance contrast ratio for every light-theme
/// text/background pairing this token set produces. Text Primary
/// (#1A1A1A) against Background Light (#FAFAFA) is 16.67:1; against
/// Surface Light (#FFFFFF) is 17.40:1. Text Secondary (#6B6B6B) — the
/// tighter case, as expected for a deliberately muted color — is 5.11:1
/// against Background Light and 5.33:1 against Surface Light. All four
/// clear the 4.5:1 floor with real margin, not marginally.
///
/// Dark-theme pairings, computed the same way now that AppTheme.dark
/// wires up the real dark-mode tokens instead of falling back to the
/// light-mode values (see that file): Text Primary Dark (#F0F0F0)
/// against Background Dark (#121212) is ~16.4:1; against Surface Dark
/// (#1E1E1E) is ~14.6:1. Text Secondary Dark (#ADADAD) — again the
/// tighter case — is ~8.4:1 against Background Dark and ~7.4:1 against
/// Surface Dark. All four clear the floor with more margin than their
/// light-theme counterparts, not less.
const double kMinimumContrastRatio = 4.5;
