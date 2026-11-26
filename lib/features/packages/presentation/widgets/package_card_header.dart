import 'package:flutter/material.dart';

import 'package_tier_icon.dart';

class PackageCardHeader extends StatelessWidget {
  const PackageCardHeader({
    required this.packageName,
    this.active = true,
    this.titleStyle,
    this.subtitle,
    this.trailing,
    super.key,
  });

  final String packageName;
  final bool active;
  final TextStyle? titleStyle;
  final Widget? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        PackageTierIcon(packageName: packageName, active: active),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                packageName,
                style: titleStyle ?? Theme.of(context).textTheme.titleLarge,
              ),
              if (subtitle case final details?) ...[
                const SizedBox(height: 4),
                details,
              ],
            ],
          ),
        ),
        if (trailing case final accessory?) ...[
          const SizedBox(width: 8),
          accessory,
        ],
      ],
    );
  }
}
