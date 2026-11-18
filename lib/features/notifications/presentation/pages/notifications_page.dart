import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../controllers/notification_controller.dart';
import '../widgets/notification_tile.dart';

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationControllerProvider);
    final unreadCount = state.when<int?>(
      data: (notifications) =>
          notifications.where((notification) => !notification.isRead).length,
      error: (_, _) => null,
      loading: () => null,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (unreadCount != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: _UnreadCounter(count: unreadCount)),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: state.when(
          data: (notifications) {
            if (notifications.isEmpty) {
              return _RefreshableEmptyState(
                onRefresh: () =>
                    ref.read(notificationControllerProvider.notifier).refresh(),
              );
            }

            return RefreshIndicator(
              color: AppColors.primary,
              backgroundColor: AppColors.surfaceElevated,
              onRefresh: () =>
                  ref.read(notificationControllerProvider.notifier).refresh(),
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  24 + MediaQuery.paddingOf(context).bottom,
                ),
                itemCount: notifications.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) =>
                    NotificationTile(notification: notifications[index]),
              ),
            );
          },
          error: (error, _) => _ErrorState(
            message: error.toString(),
            onRetry: () =>
                ref.read(notificationControllerProvider.notifier).refresh(),
          ),
          loading: () => const _LoadingState(),
        ),
      ),
    );
  }
}

class _UnreadCounter extends StatelessWidget {
  final int count;

  const _UnreadCounter({required this.count});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$count unread notifications',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: count == 0
              ? AppColors.surfaceVariant
              : AppColors.primaryContainer,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: count == 0
                ? AppColors.divider
                : AppColors.primary.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          '$count unread',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: count == 0 ? AppColors.textSecondary : AppColors.primaryDark,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Loading notifications...',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _StateIcon(icon: Icons.wifi_off_rounded, color: AppColors.error),
            const SizedBox(height: 22),
            Text(
              'Could not load notifications',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RefreshableEmptyState extends StatelessWidget {
  final Future<void> Function() onRefresh;

  const _RefreshableEmptyState({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => RefreshIndicator(
        color: AppColors.primary,
        onRefresh: onRefresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _StateIcon(
                    icon: Icons.notifications_none_rounded,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'No notifications yet',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Updates about diet plans, messages, tasks, and payments will appear here.',
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StateIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _StateIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Icon(icon, size: 40, color: color),
    );
  }
}
