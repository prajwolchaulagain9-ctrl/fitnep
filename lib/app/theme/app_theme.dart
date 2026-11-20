import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppColors {
  AppColors._();

  // Master palette from the Forgot Password experience.
  static const primary = Color(0xFFFF6B00);
  static const primaryLight = Color(0xFFFF8A33);
  static const primaryDark = Color(0xFFD95700);
  static const primaryContainer = Color(0xFFFFF0E6);

  // Backgrounds and surfaces.
  static const background = Color(0xFFFFFFFF);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceVariant = Color(0xFFF5F5F5);
  static const surfaceElevated = Color(0xFFFFFFFF);
  static const cardBackground = Color(0xFFFFFFFF);
  static const divider = Color(0xFFE2E6E9);
  static const fieldBorder = Color(0xFF7A838A);

  // Text from the Forgot Password page.
  static const textPrimary = Color(0xFF102637);
  static const textSecondary = Color(0xFF657A8C);
  static const textDisabled = Color(0xFFA8AFB4);
  static const textInverse = Color(0xFFFFFFFF);

  // Existing semantic colors remain available for application state.
  static const statusActive = Color(0xFF248A57);
  static const statusActiveContainer = Color(0xFFE9F7EF);
  static const statusInactive = Color(0xFFD94B4B);
  static const statusInactiveContainer = Color(0xFFFFECEC);
  static const statusPending = Color(0xFFD48700);
  static const statusPendingContainer = Color(0xFFFFF5DB);

  static const packageBasic = Color(0xFF3973B7);
  static const packageBasicContainer = Color(0xFFEAF2FB);
  static const packageStandard = Color(0xFF7959B7);
  static const packageStandardContainer = Color(0xFFF1ECFA);
  static const packagePremium = primary;
  static const packagePremiumContainer = primaryContainer;
  static const packageElite = Color(0xFFD48700);
  static const packageEliteContainer = Color(0xFFFFF5DB);

  static const success = statusActive;
  static const error = statusInactive;
  static const warning = statusPending;
  static const info = packageBasic;

  static const actionDeactivate = statusInactive;
  static const actionReactivate = statusActive;
  static const actionPackageChange = packageStandard;
  static const actionGeneral = packageBasic;
}

abstract final class AppTheme {
  static ThemeData get light => _build();

  // The master reference is light-only, so device dark mode uses it too.
  static ThemeData get dark => _build();

  // Kept for existing callers that use the older theme getter.
  static ThemeData get lightTheme => light;

  static ThemeData _build() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppColors.primary,
          onPrimary: AppColors.textInverse,
          surface: AppColors.surface,
          onSurface: AppColors.textPrimary,
          error: AppColors.error,
          onError: AppColors.textInverse,
        );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final textTheme = base.textTheme.copyWith(
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        color: AppColors.textPrimary,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.2,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        color: AppColors.textPrimary,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.2,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        color: AppColors.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        color: AppColors.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        color: AppColors.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: base.textTheme.titleSmall?.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(
        color: AppColors.textPrimary,
        fontSize: 16,
        height: 1.5,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        color: AppColors.textSecondary,
        fontSize: 14,
        height: 1.5,
      ),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        color: AppColors.textSecondary,
        fontSize: 12,
        height: 1.5,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        color: AppColors.textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: base.textTheme.labelMedium?.copyWith(
        color: AppColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      labelSmall: base.textTheme.labelSmall?.copyWith(
        color: AppColors.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    );

    const systemOverlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.background,
      systemNavigationBarIconBrightness: Brightness.dark,
    );
    const stadium = StadiumBorder();

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: systemOverlayStyle,
        titleTextStyle: textTheme.titleLarge,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
          shape: stadium,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textInverse,
          minimumSize: const Size(0, 52),
          elevation: 0,
          shape: stadium,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(double.infinity, 52),
          side: const BorderSide(color: AppColors.primary),
          shape: stadium,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardBackground,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.divider),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 0,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? AppColors.primary : null,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: const TextStyle(color: AppColors.textInverse),
        actionTextColor: AppColors.primaryLight,
        behavior: SnackBarBehavior.floating,
        shape: const StadiumBorder(),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      iconTheme: const IconThemeData(color: AppColors.textSecondary, size: 22),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textInverse,
        elevation: 2,
      ),
    );
  }
}
