import 'package:flutter/material.dart';

import '../../domain/entities/client_entity.dart';
import '../../../../app/theme/app_theme.dart';

class StatusBadge extends StatelessWidget {
  final ClientStatus status;
  final bool large;

  const StatusBadge({super.key, required this.status, this.large = false});

  @override
  Widget build(BuildContext context) {
    final isActive = status == ClientStatus.active;
    final color = isActive ? AppColors.statusActive : AppColors.statusInactive;
    final bgColor = isActive
        ? AppColors.statusActiveContainer
        : AppColors.statusInactiveContainer;
    final label = isActive ? 'Active' : 'Inactive';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 12 : 8,
        vertical: large ? 6 : 3,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(large ? 10 : 6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: large ? 7 : 5,
            height: large ? 7 : 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(width: large ? 6 : 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: large ? 13 : 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
