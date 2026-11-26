import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../core/constants/app_assets.dart';

// Keep the original mark while adapting its colors and tagline to the app.
class FitNepWordmark extends StatelessWidget {
  const FitNepWordmark({super.key, this.width = 140});

  static const assetPath = AppAssets.wordmark;
  static const tagline = 'Your Health Partner';
  final double width;

  @override
  Widget build(BuildContext context) {
    final height = width * 615 / 641;
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
          child: SizedBox(
            width: width,
            height: height,
            child: ColoredBox(
              color: background,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ShaderMask(
                    blendMode: BlendMode.dstIn,
                    // Fade the original badge into the background before its
                    // embedded lettering below the FitNEP name.
                    shaderCallback: (bounds) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.white, Colors.white, Colors.transparent],
                      stops: [0, .782, .816],
                    ).createShader(bounds),
                    child: ColorFiltered(
                      colorFilter: tint,
                      child: Image.asset(
                        assetPath,
                        width: width,
                        height: height,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: width * .105,
                    child: Text(
                      tagline,
                      textAlign: TextAlign.center,
                      textScaler: TextScaler.noScaling,
                      maxLines: 1,
                      style: TextStyle(
                        inherit: false,
                        color: ink,
                        fontFamily: 'Inter',
                        fontSize: width * .074,
                        fontWeight: FontWeight.w600,
                        letterSpacing: width * .001,
                        height: 1.12,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static List<double> _tintChannel(double background, double ink) {
    // The source navy has a red-minus-blue value of -26.
    final scale = (ink - background) * 255 / 254;
    return [scale, 0, -scale, 0, background * 255 + 26 * scale];
  }
}
