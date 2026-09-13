import 'package:flutter/material.dart';

/// Fulus visual tokens.
///
/// Deep navy is the primary brand/action colour. Orange is a restrained
/// commerce accent, green is semantic success, and most UI is carried by
/// neutral space and typography rather than coloured containers.
class AppColors {
  AppColors._();

  static const primary = Color(0xFF131921);
  static const brand = Color(0xFF131921);
  static const brandDark = Color(0xFF0B1116);
  static const brandLight = Color(0xFFE7EDF3);
  static const accent = Color(0xFFFF9900);
  static const accentLight = Color(0xFFFFF3E0);
  static const clay = Color(0xFFA8492E);
  static const clayLight = Color(0xFFF4DDD3);
  static const ochre = Color(0xFFC98200);

  static const success = Color(0xFF087443);
  static const successLight = Color(0xFFE3F2EC);
  static const warning = ochre;
  static const error = clay;
  static const info = Color(0xFF2E5C8A);

  static const textPrimaryLight = Color(0xFF131A22);
  static const textSecondaryLight = Color(0xFF48515B);
  static const mutedLight = Color(0xFF66717C);
  static const borderLight = Color(0xFFE1E5E8);
  static const backgroundLight = Color(0xFFF7F8F9);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceAltLight = Color(0xFFF0F2F4);

  static const backgroundDark = Color(0xFF0B1116);
  static const surfaceDark = Color(0xFF131921);
  static const surfaceAltDark = Color(0xFF1D252D);
  static const borderDark = Color(0xFF39434D);
  static const darkWarning = Color(0xFFE0A64A);
  static const darkWarningOn = Color(0xFF17120A);
  static const darkError = Color(0xFFE18A70);
  static const darkErrorOn = Color(0xFF200C07);
  static const darkPrimary = Color(0xFFDCE7F3);
  static const darkPrimaryStrong = Color(0xFFEAF2FA);
  static const darkOnPrimary = Color(0xFF101820);
  static const darkInfo = Color(0xFF7EA5C9);
  static const darkSuccess = Color(0xFF63C49B);
  static const darkSuccessOn = Color(0xFF071B12);
  static const darkTextPrimary = Color(0xFFF5F6F7);
  static const darkTextSecondary = Color(0xFFC0C7CD);
  static const darkMuted = Color(0xFF9DA7AF);

  static const neutral0 = Color(0xFFFFFFFF);
  static const neutral50 = Color(0xFFF7F8F9);
  static const neutral100 = Color(0xFFEAEDED);
  static const neutral200 = Color(0xFFD5DBE0);
  static const neutral300 = Color(0xFFB8C0C7);
  static const neutral400 = Color(0xFF929CA5);
  static const neutral500 = Color(0xFF66717C);
  static const neutral600 = Color(0xFF48515B);
  static const neutral700 = Color(0xFF303A43);
  static const neutral800 = Color(0xFF1F2830);
  static const neutral900 = Color(0xFF131A22);

  static const primary50 = Color(0xFFF1F4F7);
  static const primary100 = Color(0xFFE2E8EE);
  static const primary200 = Color(0xFFC5D0DA);
  static const primary300 = Color(0xFFA7B8C7);
  static const primary400 = Color(0xFF7F95A8);
  static const primary500 = primary;
  static const primary600 = Color(0xFF0E141B);
  static const primary700 = Color(0xFF0B1116);
  static const primary800 = Color(0xFF081018);
  static const primary900 = Color(0xFF050B10);

  static const secondary50 = Color(0xFFF4F5F6);
  static const secondary100 = Color(0xFFEAEDED);
  static const secondary200 = Color(0xFFD5DBE0);
  static const secondary300 = Color(0xFFB8C0C7);
  static const secondary400 = Color(0xFF929CA5);
  static const secondary500 = textSecondaryLight;
  static const secondary600 = Color(0xFF38424B);
  static const secondary700 = Color(0xFF2A333B);
  static const secondary800 = Color(0xFF202830);
  static const secondary900 = brandDark;

  static const info50 = Color(0xFFF0F5F9);
  static const info100 = Color(0xFFDCE8F1);
  static const info200 = Color(0xFFBDD0E0);
  static const info300 = Color(0xFF9DB8CF);
  static const info400 = Color(0xFF7096B6);
  static const info500 = info;
  static const info600 = Color(0xFF23496E);
  static const info700 = Color(0xFF1B3B59);
  static const info800 = Color(0xFF142D44);
  static const info900 = Color(0xFF0E1F2E);

  static bool isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;
  static Color primaryOf(BuildContext context) => isDark(context) ? darkPrimary : primary;
  static Color onPrimaryOf(BuildContext context) => isDark(context) ? darkOnPrimary : neutral0;
  static Color accentOf(BuildContext context) => accent;
  static Color successOf(BuildContext context) => isDark(context) ? darkSuccess : success;
  static Color successOnOf(BuildContext context) => isDark(context) ? darkSuccessOn : neutral0;
  static Color warningOf(BuildContext context) => isDark(context) ? darkWarning : warning;
  static Color warningOnOf(BuildContext context) => isDark(context) ? darkWarningOn : brand;
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

  // System-style sans typography keeps Fulus contemporary and highly
  // scannable. The previous editorial serif treatment made operational
  // screens feel like a publication rather than a modern mobile product.
  static const display = TextStyle(fontSize: 36, fontWeight: FontWeight.w800, height: 1.08, letterSpacing: -1.0);
  static const title = TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.12, letterSpacing: -0.6);
  static const heading = TextStyle(fontSize: 22, fontWeight: FontWeight.w750, height: 1.18, letterSpacing: -0.3);
  static const subheading = TextStyle(fontSize: 18, fontWeight: FontWeight.w650, height: 1.3, letterSpacing: -0.1);
  static const bodyLarge = TextStyle(fontSize: 18, height: 1.5);
  static const body = TextStyle(fontSize: 16, height: 1.5);
  static const caption = TextStyle(fontSize: 14, height: 1.45);
  static const label = TextStyle(fontSize: 13, fontWeight: FontWeight.w650, height: 1.3, letterSpacing: 0.2);
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
    BoxShadow(offset: Offset(0, 1), blurRadius: 2, color: Color(0x0A1B1B17)),
    BoxShadow(offset: Offset(0, 4), blurRadius: 14, color: Color(0x081B1B17)),
  ];
  static const liftLight = [BoxShadow(offset: Offset(0, 10), blurRadius: 26, color: Color(0x241B1B17))];
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
        colors: AppColors.isDark(context) ? [AppColors.brandDark, AppColors.brand] : [AppColors.brand, AppColors.primary700],
      );
  static LinearGradient successOf(BuildContext context) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: AppColors.isDark(context) ? [AppColors.surfaceDark, AppColors.brandDark] : [AppColors.successLight, AppColors.surfaceLight],
      );
}
