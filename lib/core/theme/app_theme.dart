import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// Material defaults translated from the Wholesale Plastic editorial system.
/// Typography and rules carry hierarchy; surfaces stay quiet and functional.
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      primary: AppColors.primary,
      onPrimary: AppColors.brand,
      error: AppColors.error,
      onError: AppColors.neutral0,
      surface: AppColors.surfaceLight,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      fontFamily: 'Inter',
      fontFamilyFallback: const ['system-ui', 'sans-serif'],
      scaffoldBackgroundColor: AppColors.backgroundLight,
      textTheme: _textTheme(AppColors.textPrimaryLight, AppColors.textSecondaryLight),
      elevatedButtonTheme: _elevatedButtonTheme(colorScheme),
      outlinedButtonTheme: _outlinedButtonTheme(AppColors.textPrimaryLight, AppColors.borderLight),
      textButtonTheme: _textButtonTheme(AppColors.textPrimaryLight),
      cardTheme: _cardTheme(AppColors.surfaceLight, AppColors.borderLight),
      inputDecorationTheme: _inputDecorationTheme(AppColors.surfaceLight, AppColors.borderLight, AppColors.brand),
      appBarTheme: _appBarTheme(AppColors.backgroundLight, AppColors.textPrimaryLight),
      dividerTheme: const DividerThemeData(color: AppColors.borderLight, thickness: 1, space: 1),
      chipTheme: _chipTheme(colorScheme, AppColors.borderLight),
      listTileTheme: _listTileTheme(AppColors.textPrimaryLight),
      pageTransitionsTheme: _pageTransitionsTheme,
    );
  }

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
      fontFamily: 'Inter',
      fontFamilyFallback: const ['system-ui', 'sans-serif'],
      scaffoldBackgroundColor: AppColors.backgroundDark,
      textTheme: _textTheme(AppColors.darkTextPrimary, AppColors.darkTextSecondary),
      elevatedButtonTheme: _elevatedButtonTheme(colorScheme),
      outlinedButtonTheme: _outlinedButtonTheme(AppColors.darkTextPrimary, AppColors.borderDark),
      textButtonTheme: _textButtonTheme(AppColors.darkTextPrimary),
      cardTheme: _cardTheme(AppColors.surfaceDark, AppColors.borderDark),
      inputDecorationTheme: _inputDecorationTheme(AppColors.surfaceDark, AppColors.borderDark, AppColors.darkTextPrimary),
      appBarTheme: _appBarTheme(AppColors.backgroundDark, AppColors.darkTextPrimary),
      dividerTheme: const DividerThemeData(color: AppColors.borderDark, thickness: 1, space: 1),
      chipTheme: _chipTheme(colorScheme, AppColors.borderDark),
      listTileTheme: _listTileTheme(AppColors.darkTextPrimary),
      pageTransitionsTheme: _pageTransitionsTheme,
    );
  }

  static TextTheme _textTheme(Color primaryText, Color secondaryText) {
    return TextTheme(
      displayLarge: AppTypography.display.copyWith(color: primaryText),
      displayMedium: AppTypography.title.copyWith(color: primaryText),
      titleLarge: AppTypography.title.copyWith(color: primaryText),
      headlineMedium: AppTypography.heading.copyWith(color: primaryText),
      titleMedium: AppTypography.subheading.copyWith(color: primaryText),
      bodyLarge: AppTypography.bodyLarge.copyWith(color: primaryText),
      bodyMedium: AppTypography.body.copyWith(color: primaryText),
      bodySmall: AppTypography.caption.copyWith(color: secondaryText),
      labelLarge: AppTypography.buttonLabel.copyWith(color: primaryText),
      labelMedium: AppTypography.label.copyWith(color: secondaryText),
    );
  }

  static ElevatedButtonThemeData _elevatedButtonTheme(ColorScheme scheme) {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        minimumSize: const Size.fromHeight(AppTouchTarget.minimum),
        textStyle: AppTypography.buttonLabel,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
    );
  }

  static OutlinedButtonThemeData _outlinedButtonTheme(Color foreground, Color border) {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: foreground,
        minimumSize: const Size.fromHeight(AppTouchTarget.minimum),
        textStyle: AppTypography.buttonLabel,
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
    );
  }

  static TextButtonThemeData _textButtonTheme(Color foreground) {
    return TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: foreground,
        minimumSize: const Size(AppTouchTarget.minimum, AppTouchTarget.minimum),
        textStyle: AppTypography.buttonLabel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
    );
  }

  static CardThemeData _cardTheme(Color surface, Color border) {
    return CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: border),
      ),
    );
  }

  static ChipThemeData _chipTheme(ColorScheme scheme, Color border) {
    return ChipThemeData(
      backgroundColor: scheme.surface,
      selectedColor: scheme.primary.withValues(alpha: 0.12),
      disabledColor: scheme.surface.withValues(alpha: 0.5),
      side: BorderSide(color: border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      labelStyle: AppTypography.label.copyWith(color: scheme.onSurface),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
    );
  }

  static ListTileThemeData _listTileTheme(Color foreground) {
    return ListTileThemeData(
      textColor: foreground,
      iconColor: foreground,
      minVerticalPadding: AppSpacing.sm,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
    );
  }

  static AppBarTheme _appBarTheme(Color background, Color foreground) {
    return AppBarTheme(
      backgroundColor: background,
      foregroundColor: foreground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: AppTypography.heading.copyWith(color: foreground),
    );
  }

  static InputDecorationTheme _inputDecorationTheme(Color surface, Color border, Color focus) {
    return InputDecorationTheme(
      floatingLabelBehavior: FloatingLabelBehavior.always,
      filled: true,
      fillColor: surface,
      labelStyle: AppTypography.label.copyWith(color: AppColors.mutedLight),
      hintStyle: AppTypography.body.copyWith(color: AppColors.mutedLight),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: focus, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: AppColors.error, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
    );
  }

  static const _pageTransitionsTheme = PageTransitionsTheme(
    builders: {TargetPlatform.android: FadeUpwardsPageTransitionsBuilder()},
  );
}
