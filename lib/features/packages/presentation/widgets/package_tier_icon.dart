import 'package:flutter/material.dart';

class PackageTierIcon extends StatelessWidget {
  const PackageTierIcon({
    required this.packageName,
    this.active = true,
    super.key,
  });

  final String packageName;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tier = packageName.trim().toLowerCase().split(RegExp(r'\s+')).first;
    final icon = switch (tier) {
      'basic' => Icons.spa_outlined,
      'standard' => Icons.insights_rounded,
      'premium' => Icons.diamond_outlined,
      'elite' => Icons.emoji_events_outlined,
      _ => Icons.inventory_2_outlined,
    };

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: active
            ? colors.primaryContainer
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        icon,
        color: active ? colors.primary : colors.onSurfaceVariant,
        size: 22,
      ),
    );
  }
}
