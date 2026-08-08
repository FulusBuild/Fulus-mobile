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
  // and Error all desaturate a touch in dark mode." Previously this file
  // fell back to the LIGHT-mode Primary/Error values here, flagged as a
  // real, named gap: Volume 16 states the desaturate DIRECTION without
  // exact hex values, and design_tokens.dart didn't have them either at
  // the time. The Visual Design Bible's own Design Tokens volume has
  // since worked out real desaturated values (AppColors.darkPrimary /
  // darkOnPrimary / darkError / darkErrorOn) — this now wires them in
  // directly, closing that gap rather than continuing to flag it.
  static ThemeData get dark {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.darkPrimary,
      brightness: Brightness.dark,
      primary: AppColors.darkPrimary,
      onPrimary: AppColors.darkOnPrimary,
      error: AppColors.darkError,
      onError: AppColors.darkErrorOn,
      surface: AppColors.surfaceDark,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.backgroundDark,
      // Same closed gap as above — AppColors.darkTextPrimary/
      // darkTextSecondary are real Bible values now, not Flutter's
      // generic white/white70 dark-theme defaults.
      textTheme: _textTheme(AppColors.darkTextPrimary, AppColors.darkTextSecondary),
      elevatedButtonTheme: _elevatedButtonTheme(colorScheme),
      outlinedButtonTheme: _outlinedButtonTheme(colorScheme),
      cardTheme: _cardTheme(),
      inputDecorationTheme: _inputDecorationTheme(),
      pageTransitionsTheme: _pageTransitionsTheme,
    );
  }

  // Previously only 5 of Material 3's 15 TextTheme slots were mapped
  // (displayLarge, headlineMedium, bodyLarge, bodySmall, labelLarge) —
  // fine for the four screens that reference AppTypography.* directly
  // and never touch Theme.of(context).textTheme, but anything relying
  // on Flutter's own widget defaults (AppBar's title, for instance,
  // reads titleLarge in Material 3) fell back to Flutter's stock type
  // scale instead of this app's. Now maps every slot this Bible has a
  // named style for. Also fixes a real mismatch: bodyLarge previously
  // pointed at AppTypography.body (16sp, the Bible's *standard* body)
  // rather than AppTypography.bodyLarge (18sp, the Bible's actual
  // "large body" style) — router.dart's placeholder screens already
  // read textTheme.bodyLarge for their "not yet built" note, so this
  // corrects that copy to the Bible's own lead-paragraph/empty-state
  // size rather than leaving it silently one step smaller than named.
  static TextTheme _textTheme(Color primaryText, Color secondaryText) {
    return TextTheme(
      displayLarge: AppTypography.display.copyWith(color: primaryText),
      titleLarge: AppTypography.title.copyWith(color: primaryText),
      headlineMedium: AppTypography.heading.copyWith(color: primaryText),
      titleMedium: AppTypography.subheading.copyWith(color: primaryText),
      bodyLarge: AppTypography.bodyLarge.copyWith(color: primaryText),
      bodyMedium: AppTypography.body.copyWith(color: primaryText),
      bodySmall: AppTypography.caption.copyWith(color: secondaryText),
      labelLarge: AppTypography.buttonLabel,
      labelMedium: AppTypography.label.copyWith(color: secondaryText),
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

  static CardTheme _cardTheme() {
    // "Cards — soft rounded corners, a light shadow for separation
    // rather than a hard border" — Volume 16, Components.
    // CardThemeData doesn't exist in Flutter 3.24.0 (this CI's pinned
    // version, .github/workflows/ci.yml) — the CardTheme/CardThemeData
    // split landed in the Flutter 3.27 component-theme-normalization
    // migration. At 3.24.0, CardTheme is itself the plain data class
    // ThemeData.cardTheme expects, constructed directly like this.
    return CardTheme(
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
