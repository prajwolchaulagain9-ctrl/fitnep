import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:animations/animations.dart';

class AppColors {
  AppColors._();
  static Color statusTone(BuildContext context, Color tone) => Color.lerp(
    tone,
    Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black,
    Theme.of(context).brightness == Brightness.dark ? .35 : .14,
  )!;
  static Color statusSurface(BuildContext context, Color tone, Color light) =>
      Theme.of(context).brightness == Brightness.dark
      ? Color.alphaBlend(
          tone.withValues(alpha: .14),
          Theme.of(context).colorScheme.surface,
        )
      : light;

  static const primary = Color(0xFF66517E);
  static const darkPrimary = Color(0xFFCBB9E4);
  static const primaryContainer = Color(0xFFE9E4F2);

  // Reverse the light and dark tones across the complete wordmark.
  static const logoBackground = Color(0xFFECE6F4);
  static const logoForeground = Color(0xFF594571);
  static const darkLogoBackground = Color(0xFF383342);
  static const darkLogoForeground = Color(0xFFE6DAF3);

  // Backgrounds
  static const background = Color(0xFFF6F5F9);
  static const surface = Color(0xFFFCFBFD);
  static const surfaceVariant = Color(0xFFEAE7F0);
  static const surfaceElevated = Color(0xFFFCFBFD);
  static const cardBackground = Color(0xFFFCFBFD);
  static const divider = Color(0xFFDBD7E4);
  static const fieldBorder = Color(0xFF79748A);

  // Text
  static const textPrimary = Color(0xFF172137);
  static const textSecondary = Color(0xFF4F596D);
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
          primary: isLight ? AppColors.primary : AppColors.darkPrimary,
          onPrimary: isLight ? Colors.white : const Color(0xFF2D2438),
          primaryContainer: isLight
              ? AppColors.primaryContainer
              : const Color(0xFF373440),
          onPrimaryContainer: isLight
              ? AppColors.textPrimary
              : const Color(0xFFF4EDF9),
          secondary: isLight
              ? const Color(0xFF45536E)
              : const Color(0xFFBFCAA9),
          onSecondary: isLight ? Colors.white : const Color(0xFF283020),
          secondaryContainer: isLight
              ? const Color(0xFFE2E7F0)
              : const Color(0xFF3A4134),
          onSecondaryContainer: isLight
              ? AppColors.textPrimary
              : const Color(0xFFE2E9D7),
          surface: isLight ? AppColors.surface : const Color(0xFF24242C),
          onSurface: isLight ? AppColors.textPrimary : const Color(0xFFF6F4FA),
          onSurfaceVariant: isLight
              ? AppColors.textSecondary
              : const Color(0xFFCBC7D2),
          surfaceContainerLowest: isLight
              ? Colors.white
              : const Color(0xFF1D1D24),
          surfaceContainerLow: isLight
              ? const Color(0xFFF1EFF5)
              : const Color(0xFF32313B),
          surfaceContainer: isLight
              ? const Color(0xFFEFEDF4)
              : const Color(0xFF373641),
          surfaceContainerHigh: isLight
              ? const Color(0xFFEDEAF2)
              : const Color(0xFF3C3A47),
          surfaceContainerHighest: isLight
              ? AppColors.surfaceVariant
              : const Color(0xFF42404D),
          outline: isLight ? AppColors.fieldBorder : const Color(0xFF938B9C),
          outlineVariant: isLight ? AppColors.divider : const Color(0xFF4C4958),
          error: isLight ? const Color(0xFFB3262F) : const Color(0xFFFFB4AB),
        );
    final background = isLight ? AppColors.background : scheme.surface;
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: background,
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
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      animationDuration: const Duration(milliseconds: 160),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(
          fontFamily: 'Inter',
          fontSize: 16,
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
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          ...base.pageTransitionsTheme.builders,
          TargetPlatform.android: const _FitNepPageTransitions(),
        },
      ),
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
        backgroundColor: background,
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
          systemNavigationBarColor: background,
          systemNavigationBarIconBrightness: isLight
              ? Brightness.dark
              : Brightness.light,
        ),
      ),
      cardTheme: CardThemeData(
        color: isLight ? scheme.surface : scheme.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      drawerTheme: DrawerThemeData(backgroundColor: scheme.surfaceContainerLow),
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
          side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
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

class _FitNepPageTransitions extends PageTransitionsBuilder {
  const _FitNepPageTransitions();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return SharedAxisTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      transitionType: SharedAxisTransitionType.horizontal,
      fillColor: Theme.of(context).scaffoldBackgroundColor,
      child: child,
    );
  }
}
