import 'package:flutter/material.dart';

/// Fulus visual tokens.
///
/// Fulus uses one brand colour and a neutral foundation: blue for brand and
/// interaction, white for surfaces, and black for typography/icons. Status
/// states use hierarchy, copy and iconography rather than introducing new
/// colours. This keeps the product recognisable and visually calm.
class AppColors {
  AppColors._();

  // Brand palette: blue + white + black.
  static const primary = Color(0xFF2563EB);
  static const brand = primary;
  static const brandDark = Color(0xFF1D4ED8);
  static const brandLight = Color(0xFFEFF4FF);

  // Semantic states intentionally stay inside the core palette.
  static const accent = primary;
  static const accentLight = brandLight;
  static const clay = Color(0xFF111111);
  static const clayLight = Color(0xFFF4F4F4);
  static const ochre = Color(0xFF111111);
  static const success = Color(0xFF111111);
  static const successLight = Color(0xFFF4F4F4);
  static const warning = Color(0xFF111111);
  static const error = Color(0xFF111111);
  static const info = primary;

  static const textPrimaryLight = Color(0xFF111111);
  static const textSecondaryLight = Color(0xFF4B4B4B);
  static const mutedLight = Color(0xFF6B6B6B);
  static const borderLight = Color(0xFFE5E7EB);
  static const backgroundLight = Color(0xFFFFFFFF);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceAltLight = Color(0xFFF7F8FA);

  // Dark mode remains monochrome + blue; no additional brand colours.
  static const backgroundDark = Color(0xFF000000);
  static const surfaceDark = Color(0xFF111111);
  static const surfaceAltDark = Color(0xFF1A1A1A);
  static const borderDark = Color(0xFF303030);
  static const darkWarning = Color(0xFFFFFFFF);
  static const darkWarningOn = Color(0xFF000000);
  static const darkError = Color(0xFFFFFFFF);
  static const darkErrorOn = Color(0xFF000000);
  static const darkPrimary = Color(0xFF60A5FA);
  static const darkPrimaryStrong = Color(0xFF93C5FD);
  static const darkOnPrimary = Color(0xFF000000);
  static const darkInfo = Color(0xFF60A5FA);
  static const darkSuccess = Color(0xFFFFFFFF);
  static const darkSuccessOn = Color(0xFF000000);
  static const darkTextPrimary = Color(0xFFFFFFFF);
  static const darkTextSecondary = Color(0xFFD1D5DB);
  static const darkMuted = Color(0xFF9CA3AF);

  static const neutral0 = Color(0xFFFFFFFF);
  static const neutral50 = Color(0xFFF9FAFB);
  static const neutral100 = Color(0xFFF3F4F6);
  static const neutral200 = Color(0xFFE5E7EB);
  static const neutral300 = Color(0xFFD1D5DB);
  static const neutral400 = Color(0xFF9CA3AF);
  static const neutral500 = Color(0xFF6B7280);
  static const neutral600 = Color(0xFF4B5563);
  static const neutral700 = Color(0xFF374151);
  static const neutral800 = Color(0xFF1F2937);
  static const neutral900 = Color(0xFF111111);

  static const primary50 = Color(0xFFEFF4FF);
  static const primary100 = Color(0xFFDBEAFE);
  static const primary200 = Color(0xFFBFDBFE);
  static const primary300 = Color(0xFF93C5FD);
  static const primary400 = Color(0xFF60A5FA);
  static const primary500 = primary;
  static const primary600 = Color(0xFF1D4ED8);
  static const primary700 = Color(0xFF1E40AF);
  static const primary800 = Color(0xFF1E3A8A);
  static const primary900 = Color(0xFF172554);

  static const secondary50 = Color(0xFFF9FAFB);
  static const secondary100 = Color(0xFFF3F4F6);
  static const secondary200 = Color(0xFFE5E7EB);
  static const secondary300 = Color(0xFFD1D5DB);
  static const secondary400 = Color(0xFF9CA3AF);
  static const secondary500 = textSecondaryLight;
  static const secondary600 = Color(0xFF374151);
  static const secondary700 = Color(0xFF1F2937);
  static const secondary800 = Color(0xFF111111);
  static const secondary900 = Color(0xFF000000);

  static const info50 = primary50;
  static const info100 = primary100;
  static const info200 = primary200;
  static const info300 = primary300;
  static const info400 = primary400;
  static const info500 = info;
  static const info600 = primary600;
  static const info700 = primary700;
  static const info800 = primary800;
  static const info900 = primary900;

  static bool isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;
  static Color primaryOf(BuildContext context) => isDark(context) ? darkPrimary : primary;
  static Color onPrimaryOf(BuildContext context) => isDark(context) ? darkOnPrimary : neutral0;
  static Color accentOf(BuildContext context) => primaryOf(context);
  static Color successOf(BuildContext context) => isDark(context) ? darkSuccess : success;
  static Color successOnOf(BuildContext context) => isDark(context) ? darkSuccessOn : neutral0;
  static Color warningOf(BuildContext context) => isDark(context) ? darkWarning : warning;
  static Color warningOnOf(BuildContext context) => isDark(context) ? darkWarningOn : neutral0;
  static Color errorOf(BuildContext context) => isDark(context) ? darkError : error;
  static Color errorOnOf(BuildContext context) => isDark(context) ? darkErrorOn : neutral0;
  static Color infoOf(BuildContext context) => isDark(context) ? darkInfo : info;
  static Color backgroundOf(BuildContext context) => isDark(context) ? backgroundDark : backgroundLight;
  static Color surfaceOf(BuildContext context) => isDark(context) ? surfaceDark : surfaceLight;
  static Color surfaceAltOf(BuildContext context) => isDark(context) ? surfaceAltDark : surfaceAltLight;
  static Color borderOf(BuildContext context) => isDark(context) ? borderDark : borderLight;
  static Color textPrimaryOf(BuildContext context) => isDark(context) ? darkTextPrimary : textPrimaryLight;
  static Color textSecondaryOf(BuildContext context) => isDark(context) ? darkTextSecondary : textSecondaryLight;
  static Color mutedOf(BuildContext context) => isDark(context) ? darkMuted : mutedLight;
  static Color selectedTintOf(BuildContext context) => isDark(context) ? darkPrimary.withValues(alpha: AppOpacity.badgeTintDark) : primary50;
}

class AppTypography {
  AppTypography._();
  static const display = TextStyle(fontSize: 36, fontWeight: FontWeight.w800, height: 1.08, letterSpacing: -1.0);
  static const title = TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.12, letterSpacing: -0.6);
  static const heading = TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.18, letterSpacing: -0.3);
  static const subheading = TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.3, letterSpacing: -0.1);
  static const bodyLarge = TextStyle(fontSize: 18, height: 1.5);
  static const body = TextStyle(fontSize: 16, height: 1.5);
  static const caption = TextStyle(fontSize: 14, height: 1.45);
  static const label = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.3, letterSpacing: 0.2);
  static const buttonLabel = TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.2, letterSpacing: 0.1);
  static const mono = TextStyle(fontFamily: 'Space Mono', fontFamilyFallback: ['monospace'], fontSize: 16, height: 1.25, fontFeatures: [FontFeature.tabularFigures()]);
}

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

class AppRadius {
  AppRadius._();
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 18.0;
  static const xl = 24.0;
  static const pill = 999.0;
}

class AppElevation {
  AppElevation._();
  static const cardLight = [
    BoxShadow(offset: Offset(0, 1), blurRadius: 2, color: Color(0x0A000000)),
    BoxShadow(offset: Offset(0, 4), blurRadius: 14, color: Color(0x08000000)),
  ];
  static const liftLight = [BoxShadow(offset: Offset(0, 10), blurRadius: 26, color: Color(0x18000000))];
  static const cardDark = [BoxShadow(offset: Offset(0, 2), blurRadius: 6, color: Color(0x55000000))];
  static const liftDark = [BoxShadow(offset: Offset(0, 10), blurRadius: 26, color: Color(0x77000000))];
  static List<BoxShadow> cardOf(BuildContext context) => isDark(context) ? cardDark : cardLight;
  static List<BoxShadow> liftOf(BuildContext context) => isDark(context) ? liftDark : liftLight;
  static bool isDark(BuildContext context) => AppColors.isDark(context);
}

class AppOpacity {
  AppOpacity._();
  static const groundShadow = 0.06;
  static const subtleTintDark = 0.08;
  static const badgeTintDark = 0.14;
  static const disabled = 0.4;
  static const scrim = 0.45;
}

class AppTouchTarget {
  AppTouchTarget._();
  static const minimum = 48.0;
}

class AppMotion {
  AppMotion._();
  static const fast = Duration(milliseconds: 150);
  static const standard = Duration(milliseconds: 220);
  static const ceiling = Duration(milliseconds: 320);
  static const curveStandard = Cubic(0.4, 0.0, 0.2, 1.0);
  static const curveDecelerate = Cubic(0.0, 0.0, 0.2, 1.0);
}

class AppIconSize {
  AppIconSize._();
  static const dense = 16.0;
  static const compact = 20.0;
  static const base = 24.0;
  static const emphasis = 32.0;
  static const hero = 48.0;
  static const strokeWidth = 2.0;
}

const double kMinimumContrastRatio = 4.5;

class AppGradients {
  AppGradients._();

  static LinearGradient heroOf(BuildContext context) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: AppColors.isDark(context) ? [AppColors.brandDark, AppColors.primary700] : [AppColors.primary, AppColors.primary600],
      );

  static LinearGradient successOf(BuildContext context) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: AppColors.isDark(context) ? [AppColors.surfaceDark, AppColors.backgroundDark] : [AppColors.successLight, AppColors.surfaceLight],
      );
}
