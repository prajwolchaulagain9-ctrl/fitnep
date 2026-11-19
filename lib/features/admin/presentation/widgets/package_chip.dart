import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';

class PackageChip extends StatelessWidget {
  final String packageName;
  final bool large;

  const PackageChip({super.key, required this.packageName, this.large = false});

  Color get _color {
    switch (packageName.toLowerCase()) {
      case 'basic':
        return AppColors.packageBasic;
      case 'standard':
        return AppColors.packageStandard;
      case 'premium':
        return AppColors.packagePremium;
      case 'elite':
        return AppColors.packageElite;
      default:
        return AppColors.info;
    }
  }

  Color get _bgColor {
    switch (packageName.toLowerCase()) {
      case 'basic':
        return AppColors.packageBasicContainer;
      case 'standard':
        return AppColors.packageStandardContainer;
      case 'premium':
        return AppColors.packagePremiumContainer;
      case 'elite':
        return AppColors.packageEliteContainer;
      default:
        return AppColors.surfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 12 : 7,
        vertical: large ? 5 : 3,
      ),
      decoration: BoxDecoration(
        color: _bgColor,
        borderRadius: BorderRadius.circular(large ? 8 : 5),
        border: Border.all(color: _color.withValues(alpha: 0.35)),
      ),
      child: Text(
        packageName,
        style: TextStyle(
          color: _color,
          fontSize: large ? 13 : 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
