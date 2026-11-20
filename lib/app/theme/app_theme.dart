import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppColors {
  AppColors._();

  // Brand palette inspired by the FitNep Figma design.
  static const primary = Color(0xFFFA6B09);
  static const primaryLight = Color(0xFFFF8A33);
  static const primaryDark = Color(0xFFD95700);
  static const primaryContainer = Color(0xFFFFF0E6);

  // Backgrounds
  static const background = Color(0xFFFFFFFF);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceVariant = Color(0xFFF5F5F5);
  static const surfaceElevated = Color(0xFFFFFFFF);
  static const cardBackground = Color(0xFFFFFFFF);
  static const divider = Color(0xFFE2E6E9);
  static const fieldBorder = Color(0xFF2E4F63);

  // Text
  static const textPrimary = Color(0xFF0C1F2A);
  static const textSecondary = Color(0xFF657A8C);
  static const textDisabled = Color(0xFFA8AFB4);
  static const textInverse = Color(0xFFFFFFFF);

  // Status
  static const statusActive = Color(0xFF248A57);
  static const statusActiveContainer = Color(0xFFE9F7EF);
  static const statusInactive = Color(0xFFD94B4B);
  static const statusInactiveContainer = Color(0xFFFFECEC);
  static const statusPending = Color(0xFFD48700);
  static const statusPendingContainer = Color(0xFFFFF5DB);

  // Package colors
  static const packageBasic = Color(0xFF3973B7);
  static const packageBasicContainer = Color(0xFFEAF2FB);
  static const packageStandard = Color(0xFF7959B7);
  static const packageStandardContainer = Color(0xFFF1ECFA);
  static const packagePremium = Color(0xFFFA6B09);
  static const packagePremiumContainer = Color(0xFFFFF0E6);
  static const packageElite = Color(0xFFD48700);
  static const packageEliteContainer = Color(0xFFFFF5DB);

  // Semantic
  static const success = Color(0xFF248A57);
  static const error = Color(0xFFD94B4B);
  static const warning = Color(0xFFD48700);
  static const info = Color(0xFF3973B7);

  // Audit action colors
  static const actionDeactivate = Color(0xFFD94B4B);
  static const actionReactivate = Color(0xFF248A57);
  static const actionPackageChange = Color(0xFF7959B7);
  static const actionGeneral = Color(0xFF3973B7);
}

abstract final class AppTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);
  // Retain the merged contribution's public name without a second theme.
  static ThemeData get lightTheme => light;

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: brightness,
        ).copyWith(
          primary: isLight ? AppColors.primary : AppColors.primaryLight,
          onPrimary: isLight ? Colors.white : AppColors.textPrimary,
          primaryContainer: isLight
              ? AppColors.primaryContainer
              : const Color(0xFF49260F),
          onPrimaryContainer: isLight
              ? AppColors.primaryDark
              : const Color(0xFFFFDCC5),
          surface: isLight ? AppColors.surface : const Color(0xFF101D27),
          onSurface: isLight ? AppColors.textPrimary : const Color(0xFFF4F5F6),
          onSurfaceVariant: isLight
              ? AppColors.textSecondary
              : const Color(0xFFB9C7CE),
          surfaceContainerHighest: isLight
              ? AppColors.surfaceVariant
              : const Color(0xFF1C2B36),
          outline: isLight ? AppColors.fieldBorder : const Color(0xFF78909E),
          outlineVariant: isLight ? AppColors.divider : const Color(0xFF354652),
          error: isLight ? AppColors.error : const Color(0xFFFFB4AB),
        );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: scheme.surface,
    );
    final text = base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
    final buttonStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 52)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
      shape: const WidgetStatePropertyAll(StadiumBorder()),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(
          fontFamily: 'Inter',
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: color, width: width),
        );
    return base.copyWith(
      textTheme: text.copyWith(
        headlineLarge: text.headlineLarge?.copyWith(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          height: 1.2,
          letterSpacing: -0.5,
        ),
        headlineMedium: text.headlineMedium?.copyWith(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
        headlineSmall: text.headlineSmall?.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: text.titleLarge?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: text.titleMedium?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: text.bodyLarge?.copyWith(fontSize: 16, height: 1.5),
        bodyMedium: text.bodyMedium?.copyWith(fontSize: 16, height: 1.5),
        bodySmall: text.bodySmall?.copyWith(
          fontSize: 12,
          height: 1.5,
          color: scheme.onSurfaceVariant,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
          statusBarBrightness: brightness,
          systemNavigationBarColor: scheme.surface,
          systemNavigationBarIconBrightness: isLight
              ? Brightness.dark
              : Brightness.light,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 16),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: border(scheme.outline),
        enabledBorder: border(scheme.outline),
        focusedBorder: border(scheme.primary, 1.5),
        errorBorder: border(scheme.error),
        focusedErrorBorder: border(scheme.error, 1.5),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
      ),
      filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: buttonStyle.copyWith(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? scheme.onSurface.withValues(alpha: 0.12)
                : scheme.primary,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? scheme.onSurface.withValues(alpha: 0.38)
                : scheme.onPrimary,
          ),
          elevation: const WidgetStatePropertyAll(0),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: buttonStyle.copyWith(
          foregroundColor: WidgetStatePropertyAll(scheme.onSurface),
          side: WidgetStatePropertyAll(
            BorderSide(color: scheme.outlineVariant),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isLight ? AppColors.primaryDark : scheme.primary,
          minimumSize: const Size(48, 48),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      listTileTheme: ListTileThemeData(
        textColor: scheme.onSurface,
        iconColor: scheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 22),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
    );
  }
}
