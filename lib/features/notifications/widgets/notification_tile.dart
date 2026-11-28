import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_theme.dart';
import '../data/notification_entity.dart';

class NotificationTile extends StatelessWidget {
  final NotificationEntity notification;
  final VoidCallback? onTap;

  const NotificationTile({super.key, required this.notification, this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = _accentColor(context);
    final isUnread = !notification.isRead;
    final backgroundColor = isUnread
        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.055)
        : Theme.of(context).colorScheme.surface;
    final borderColor = isUnread
        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.32)
        : Theme.of(context).colorScheme.outlineVariant;

    return Semantics(
      container: true,
      button: onTap != null,
      label:
          '${isUnread ? 'Unread' : 'Read'} notification. '
          '${notification.title}. ${notification.message}',
      child: Material(
        color: backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: accent.withValues(alpha: 0.25)),
                  ),
                  child: Icon(_icon, color: accent, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              notification.title,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface,
                                    fontWeight: isUnread
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                    height: 1.25,
                                  ),
                            ),
                          ),
                          if (isUnread) ...[
                            const SizedBox(width: 10),
                            Container(
                              width: 9,
                              height: 9,
                              margin: const EdgeInsets.only(top: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        notification.message,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 14,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              DateFormat('MMM d, yyyy • h:mm a')
                                  .format(notification.createdAt.toLocal()),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    letterSpacing: 0,
                                  ),
                            ),
                          ),
                          if (isUnread)
                            Text(
                              'Unread',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData get _icon => switch (notification.type) {
    NotificationType.dietPlan => Icons.restaurant_menu_rounded,
    NotificationType.message => Icons.chat_bubble_outline_rounded,
    NotificationType.task => Icons.task_alt_rounded,
    NotificationType.payment => Icons.payments_outlined,
    NotificationType.assignment => Icons.person_pin_outlined,
    NotificationType.intake ||
    NotificationType.membership ||
    NotificationType.other => Icons.notifications_none_rounded,
  };

  Color _accentColor(BuildContext context) => switch (notification.type) {
    NotificationType.dietPlan => AppColors.success,
    NotificationType.message => AppColors.info,
    NotificationType.task => AppColors.actionPackageChange,
    NotificationType.payment => AppColors.warning,
    NotificationType.assignment => Theme.of(context).colorScheme.primary,
    NotificationType.intake ||
    NotificationType.membership ||
    NotificationType.other => Theme.of(context).colorScheme.primary,
  };
}
