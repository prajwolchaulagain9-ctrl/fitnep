import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../core/constants/app_assets.dart';

// Keep the original artwork while adapting its two colors to the theme.
class FitNepWordmark extends StatelessWidget {
  const FitNepWordmark({super.key, this.width = 140});

  static const assetPath = AppAssets.wordmark;
  final double width;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark
        ? AppColors.darkLogoBackground
        : AppColors.logoBackground;
    final ink = dark ? AppColors.darkLogoForeground : AppColors.logoForeground;
    final tint = ColorFilter.matrix([
      ..._tintChannel(background.r, ink.r),
      ..._tintChannel(background.g, ink.g),
      ..._tintChannel(background.b, ink.b),
      0,
      0,
      0,
      1,
      0,
    ]);
    return Semantics(
      label: 'FitNEP',
      image: true,
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(width * .27),
          child: ColorFiltered(
            colorFilter: tint,
            child: Image.asset(
              assetPath,
              width: width,
              height: width * 615 / 641,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
      ),
    );
  }

  static List<double> _tintChannel(double background, double ink) {
    // Red minus blue separates the orange artwork from its navy backdrop.
    final scale = (ink - background) * 255 / 254;
    return [scale, 0, -scale, 0, background * 255 + 14 * scale];
  }
}
