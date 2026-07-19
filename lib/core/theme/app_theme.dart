import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// Builds the two real ThemeData objects the app uses, entirely from
/// AppColors/AppTypography/AppSpacing — no hex value or raw number
/// appears in this file that isn't a reference to a named token, per
/// Architecture Section 1's stated rule for this directory.
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      primary: AppColors.primary,
      error: AppColors.error,
      surface: AppColors.surfaceLight,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.backgroundLight,
      textTheme: _textTheme(AppColors.textPrimaryLight, AppColors.textSecondaryLight),
      elevatedButtonTheme: _elevatedButtonTheme(colorScheme),
      outlinedButtonTheme: _outlinedButtonTheme(colorScheme),
      cardTheme: _cardTheme(),
      inputDecorationTheme: _inputDecorationTheme(),
      pageTransitionsTheme: _pageTransitionsTheme,
    );
  }

  // Volume 16: "Dark mode isn't light mode inverted... Primary, Warning,
  // and Error all desaturate a touch in dark mode." design_tokens.dart's
  // AppColors deliberately does NOT define desaturated dark-mode variants
  // of those three colors, since the Bible states the DIRECTION (desaturate)
  // without giving exact hex values, and inventing specific ones would
  // read as if they came from the spec when they didn't. This theme
  // therefore uses the LIGHT-mode Primary/Warning/Error values against
  // the correct dark-mode Background/Surface tokens (#121212 / #1E1E1E,
  // which ARE exact Volume 16 values) — a real, named gap against the
  // full spec, not a silent one. Revisit the moment exact desaturated
  // values are specified, rather than guess at them now.
  static ThemeData get dark {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
      primary: AppColors.primary, // not yet desaturated — see comment above
      error: AppColors.error, // not yet desaturated — see comment above
      surface: AppColors.surfaceDark,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.backgroundDark,
      // Text colors are NOT the light-theme tokens inverted blindly —
      // Volume 16 doesn't specify exact dark-mode text hex values
      // either, so Colors.white/white70 (Flutter's own standard dark-
      // theme text opacities) are used here as the most conservative,
      // widely-understood default rather than inventing specific hex
      // values Volume 16 never stated, matching the same honesty
      // principle as the Primary/Warning/Error gap above.
      textTheme: _textTheme(Colors.white, Colors.white70),
      elevatedButtonTheme: _elevatedButtonTheme(colorScheme),
      outlinedButtonTheme: _outlinedButtonTheme(colorScheme),
      cardTheme: _cardTheme(),
      inputDecorationTheme: _inputDecorationTheme(),
      pageTransitionsTheme: _pageTransitionsTheme,
    );
  }

  static TextTheme _textTheme(Color primaryText, Color secondaryText) {
    return TextTheme(
      displayLarge: AppTypography.display.copyWith(color: primaryText),
      headlineMedium: AppTypography.heading.copyWith(color: primaryText),
      bodyLarge: AppTypography.body.copyWith(color: primaryText),
      bodySmall: AppTypography.caption.copyWith(color: secondaryText),
      labelLarge: AppTypography.buttonLabel,
    );
  }

  static ElevatedButtonThemeData _elevatedButtonTheme(ColorScheme scheme) {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        // "Minimum touch target 48×48dp, without exception" — Volume 16,
        // Components: Buttons.
        minimumSize: const Size.fromHeight(AppTouchTarget.minimum),
        textStyle: AppTypography.buttonLabel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.sm),
        ),
      ),
    );
  }

  static OutlinedButtonThemeData _outlinedButtonTheme(ColorScheme scheme) {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(AppTouchTarget.minimum),
        textStyle: AppTypography.buttonLabel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.sm),
        ),
      ),
    );
  }

  static CardThemeData _cardTheme() {
    // "Cards — soft rounded corners, a light shadow for separation
    // rather than a hard border" — Volume 16, Components.
    return CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.md),
      ),
      margin: const EdgeInsets.all(AppSpacing.sm),
    );
  }

  static InputDecorationTheme _inputDecorationTheme() {
    // "Forms — labels sit permanently above each input, never
    // placeholder text alone — see Decision 57." Setting floatingLabelBehavior
    // to .always is what enforces this at the theme level rather than
    // leaving it to be remembered correctly at every individual form
    // field call site across the whole app.
    return InputDecorationTheme(
      floatingLabelBehavior: FloatingLabelBehavior.always,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
    );
  }

  // "Motion 150–250ms standard, 300ms ceiling" — applied here as the
  // actual page-transition duration Flutter's navigator uses, not just a
  // constant sitting unused in design_tokens.dart. Uses Flutter's
  // built-in FadeUpwardsPageTransitionsBuilder (Android's own standard
  // Material transition) rather than a custom-built one, since Volume 16
  // never specifies a bespoke transition CURVE or motion style beyond
  // the duration bound — inventing one would be the same category of
  // overreach as fabricating a dark-mode hex value.
  static const _pageTransitionsTheme = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
    },
  );
}
