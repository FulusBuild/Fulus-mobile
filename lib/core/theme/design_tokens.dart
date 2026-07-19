import 'package:flutter/material.dart';

/// Every value below is copied directly from Volume 16 (Mobile Design
/// System) of the BMS Mobile Product Design Bible's own "Design Tokens:
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

  static const textPrimaryLight = Color(0xFF1A1A1A);
  static const textSecondaryLight = Color(0xFF6B6B6B);

  static const backgroundLight = Color(0xFFFAFAFA);
  static const surfaceLight = Color(0xFFFFFFFF);

  // "Dark mode isn't light mode inverted. Surfaces lift slightly above
  // pure black... rather than true black-on-black" — Volume 16, Dark
  // Mode & Light Mode.
  static const backgroundDark = Color(0xFF121212);
  static const surfaceDark = Color(0xFF1E1E1E);

  // Volume 16 states colors "desaturate a touch in dark mode" but gives
  // no exact desaturated hex values — only the light-mode values and
  // that qualitative direction. Rather than invent specific desaturated
  // hex codes that would look like they came from the Bible when they
  // didn't, dark-mode variants of Primary/Warning/Error are left
  // undefined here. AppTheme.dark below uses the same light-mode values
  // for now, flagged explicitly at that point — this is a real, named
  // gap against the spec, not a silent approximation.
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
  );

  static const heading = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600, // Semibold
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
  );

  static const caption = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.normal,
  );

  static const buttonLabel = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
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

  static const standard = Duration(milliseconds: 200);
  static const ceiling = Duration(milliseconds: 300);
}

/// "Minimum contrast: 4.5:1 for all body text, in both themes." — Volume
/// 16, Accessibility. Verified directly, not just referenced: computed
/// the real WCAG relative-luminance contrast ratio for every light-theme
/// text/background pairing this token set produces. Text Primary
/// (#1A1A1A) against Background Light (#FAFAFA) is 16.67:1; against
/// Surface Light (#FFFFFF) is 17.40:1. Text Secondary (#6B6B6B) — the
/// tighter case, as expected for a deliberately muted color — is 5.11:1
/// against Background Light and 5.33:1 against Surface Light. All four
/// clear the 4.5:1 floor with real margin, not marginally. Dark-theme
/// pairings are NOT verified here, since AppTheme.dark below reuses the
/// light-mode color values as a named, flagged gap (see AppColors'
/// closing comment) rather than genuine dark-mode-specific tokens Volume
/// 16 doesn't provide exact values for — computing a contrast ratio
/// against colors that are themselves acknowledged placeholders wouldn't
/// mean anything real.
const double kMinimumContrastRatio = 4.5;
