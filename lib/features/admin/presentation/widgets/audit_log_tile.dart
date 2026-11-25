import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/audit_log_entity.dart';
import '../../../../app/theme/app_theme.dart';

class AuditLogTile extends StatelessWidget {
  final AuditLogEntity log;
  final bool isLast;

  const AuditLogTile({super.key, required this.log, this.isLast = false});

  Color get _actionColor {
    switch (log.actionType) {
      case AuditActionType.clientDeactivated:
        return AppColors.actionDeactivate;
      case AuditActionType.clientReactivated:
        return AppColors.actionReactivate;
      case AuditActionType.packageChanged:
        return AppColors.actionPackageChange;
      default:
        return AppColors.actionGeneral;
    }
  }

  IconData get _actionIcon {
    switch (log.actionType) {
      case AuditActionType.clientDeactivated:
        return Icons.block_rounded;
      case AuditActionType.clientReactivated:
        return Icons.check_circle_outline_rounded;
      case AuditActionType.packageChanged:
        return Icons.inventory_2_outlined;
      case AuditActionType.paymentRecorded:
        return Icons.credit_card_rounded;
      case AuditActionType.profileUpdated:
        return Icons.edit_outlined;
      case AuditActionType.authorizationDenied:
        return Icons.lock_outline;
      case AuditActionType.userRoleChanged:
        return Icons.manage_accounts_outlined;
      case AuditActionType.accountStatusChanged:
        return Icons.person_outline;
      case AuditActionType.clientAssignmentChanged:
        return Icons.group_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _actionColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Icon(_actionIcon, color: color, size: 20),
          ),
          const SizedBox(width: 14),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        log.actionType.displayName,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      _formatTimestamp(log.timestamp),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                RichText(
                  text: TextSpan(
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                    children: [
                      TextSpan(
                        text: log.adminName,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      TextSpan(text: ' → '),
                      TextSpan(
                        text: log.clientName,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (log.reason != null && log.reason!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Text(
                      '"${log.reason}"',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
                if (log.details != null) ...[
                  const SizedBox(height: 6),
                  Text(log.details!),
                ],
                if (!isLast) ...[const SizedBox(height: 14), const Divider()],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('dd MMM yyyy, HH:mm').format(dt);
  }
}
