import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'design_tokens.dart';
import 'fulus_icons.dart';

/// Product-wide Material foundation for Fulus.
///
/// Fulus has one interaction colour: blue. White carries the canvas and
/// primary surfaces, while black carries typography and neutral iconography.
/// Semantic states deliberately reuse this same visual language instead of
/// introducing additional status colours.
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      primary: AppColors.primary,
      onPrimary: AppColors.neutral0,
      secondary: AppColors.primary,
      onSecondary: AppColors.neutral0,
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
      iconTheme: fulusIconTheme,
      elevatedButtonTheme: _elevatedButtonTheme(colorScheme),
      outlinedButtonTheme: _outlinedButtonTheme(AppColors.textPrimaryLight, AppColors.borderLight),
      textButtonTheme: _textButtonTheme(AppColors.primary),
      cardTheme: _cardTheme(AppColors.surfaceLight),
      inputDecorationTheme: _inputDecorationTheme(AppColors.surfaceLight, AppColors.borderLight, AppColors.primary, AppColors.mutedLight),
      appBarTheme: _appBarTheme(AppColors.backgroundLight, AppColors.textPrimaryLight),
      dividerTheme: const DividerThemeData(color: AppColors.borderLight, thickness: 1, space: 1),
      chipTheme: _chipTheme(colorScheme, AppColors.borderLight),
      listTileTheme: _listTileTheme(AppColors.textPrimaryLight),
      dialogTheme: _dialogTheme(AppColors.surfaceLight, AppColors.textPrimaryLight),
      bottomSheetTheme: _bottomSheetTheme(AppColors.surfaceLight, AppColors.borderLight),
      floatingActionButtonTheme: _fabTheme(colorScheme),
      snackBarTheme: _snackBarTheme(colorScheme),
      pageTransitionsTheme: _pageTransitionsTheme,
      splashFactory: InkSparkle.splashFactory,
    );
  }

  static ThemeData get dark {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.darkPrimary,
      brightness: Brightness.dark,
      primary: AppColors.darkPrimary,
      onPrimary: AppColors.darkOnPrimary,
      secondary: AppColors.darkPrimary,
      onSecondary: AppColors.darkOnPrimary,
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
      iconTheme: fulusIconTheme,
      elevatedButtonTheme: _elevatedButtonTheme(colorScheme),
      outlinedButtonTheme: _outlinedButtonTheme(AppColors.darkTextPrimary, AppColors.borderDark),
      textButtonTheme: _textButtonTheme(AppColors.darkPrimary),
      cardTheme: _cardTheme(AppColors.surfaceDark),
      inputDecorationTheme: _inputDecorationTheme(AppColors.surfaceDark, AppColors.borderDark, AppColors.darkPrimary, AppColors.darkMuted),
      appBarTheme: _appBarTheme(AppColors.backgroundDark, AppColors.darkTextPrimary),
      dividerTheme: const DividerThemeData(color: AppColors.borderDark, thickness: 1, space: 1),
      chipTheme: _chipTheme(colorScheme, AppColors.borderDark),
      listTileTheme: _listTileTheme(AppColors.darkTextPrimary),
      dialogTheme: _dialogTheme(AppColors.surfaceDark, AppColors.darkTextPrimary),
      bottomSheetTheme: _bottomSheetTheme(AppColors.surfaceDark, AppColors.borderDark),
      floatingActionButtonTheme: _fabTheme(colorScheme),
      snackBarTheme: _snackBarTheme(colorScheme),
      pageTransitionsTheme: _pageTransitionsTheme,
      splashFactory: InkSparkle.splashFactory,
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
        disabledBackgroundColor: scheme.primary.withValues(alpha: AppOpacity.disabled),
        disabledForegroundColor: scheme.onPrimary.withValues(alpha: AppOpacity.disabled),
        minimumSize: const Size.fromHeight(52),
        textStyle: AppTypography.buttonLabel,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
    );
  }

  static OutlinedButtonThemeData _outlinedButtonTheme(Color foreground, Color border) {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: foreground,
        minimumSize: const Size.fromHeight(52),
        textStyle: AppTypography.buttonLabel,
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
    );
  }

  static TextButtonThemeData _textButtonTheme(Color foreground) {
    return TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: foreground,
        minimumSize: const Size(AppTouchTarget.minimum, AppTouchTarget.minimum),
        textStyle: AppTypography.buttonLabel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
    );
  }

  static CardThemeData _cardTheme(Color surface) {
    return CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
    );
  }

  static ChipThemeData _chipTheme(ColorScheme scheme, Color border) {
    return ChipThemeData(
      backgroundColor: scheme.surface,
      selectedColor: scheme.primary.withValues(alpha: 0.10),
      disabledColor: scheme.surface.withValues(alpha: 0.5),
      side: BorderSide(color: border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
      labelStyle: AppTypography.label.copyWith(color: scheme.onSurface),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
    );
  }

  static ListTileThemeData _listTileTheme(Color foreground) {
    return ListTileThemeData(
      textColor: foreground,
      iconColor: foreground,
      minVerticalPadding: AppSpacing.sm,
      horizontalTitleGap: AppSpacing.md,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
    );
  }

  static DialogThemeData _dialogTheme(Color surface, Color foreground) {
    return DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
      titleTextStyle: AppTypography.heading.copyWith(color: foreground),
      contentTextStyle: AppTypography.body.copyWith(color: foreground),
    );
  }

  static BottomSheetThemeData _bottomSheetTheme(Color surface, Color dragHandle) {
    return BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      showDragHandle: true,
      dragHandleColor: dragHandle,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
    );
  }

  static FloatingActionButtonThemeData _fabTheme(ColorScheme scheme) {
    return FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 2,
      focusElevation: 3,
      hoverElevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
    );
  }

  static SnackBarThemeData _snackBarTheme(ColorScheme scheme) {
    return SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: AppTypography.body.copyWith(color: scheme.onInverseSurface),
      actionTextColor: scheme.inversePrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.lg),
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
      titleSpacing: AppSpacing.lg,
      titleTextStyle: AppTypography.heading.copyWith(color: foreground),
    );
  }

  static InputDecorationTheme _inputDecorationTheme(Color surface, Color border, Color focus, Color muted) {
    return InputDecorationTheme(
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      filled: true,
      fillColor: surface,
      labelStyle: AppTypography.caption.copyWith(color: muted),
      hintStyle: AppTypography.body.copyWith(color: muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: focus, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: AppColors.error, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
    );
  }

  static const _pageTransitionsTheme = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    },
  );
}
