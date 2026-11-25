import 'package:flutter/material.dart';

import '../../core/constants/app_assets.dart';

// Original Figma image fill from node 4:994, with its rounded display shape.
class FitNepWordmark extends StatelessWidget {
  const FitNepWordmark({super.key, this.width = 140});

  static const assetPath = AppAssets.wordmark;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'FitNEP',
      image: true,
      child: ExcludeSemantics(
        child: ClipOval(
          child: Image.asset(
            assetPath,
            width: width,
            height: width * 615 / 641,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }
}
