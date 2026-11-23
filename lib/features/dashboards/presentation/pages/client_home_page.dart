import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/app_routes.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../shared/widgets/fitnep_wordmark.dart';
import '../../../authentication/presentation/sign_out_to_welcome.dart';
import '../../../notifications/presentation/controllers/notification_controller.dart';
import '../../../purchases/presentation/controllers/membership_controller.dart';

class ClientHomePage extends ConsumerWidget {
  static const notificationButtonKey = Key('client_notification_button');
  static const notificationBadgeKey = Key('client_notification_badge');

  const ClientHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(unreadNotificationCountProvider);
    final purchase = ref.watch(membershipControllerProvider).purchase;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        titleSpacing: 16,
        title: const _ClientAppBarTitle(),
        actions: [
          IconButton(
            tooltip: 'Privacy preferences',
            onPressed: () => context.push(AppRoutes.clientPrivacyPreferences),
            icon: const Icon(Icons.privacy_tip_outlined),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => signOutToWelcome(context, ref),
            icon: const Icon(Icons.logout_rounded),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Semantics(
              button: true,
              label: unreadCount > 0
                  ? 'Notifications, $unreadCount unread'
                  : 'Notifications',
              child: IconButton(
                key: notificationButtonKey,
                tooltip: 'Notifications',
                onPressed: () => context.push(AppRoutes.clientNotifications),
                icon: unreadCount > 0
                    ? Badge.count(
                        key: notificationBadgeKey,
                        count: unreadCount,
                        maxCount: 99,
                        backgroundColor: AppColors.primary,
                        textColor: AppColors.textInverse,
                        child: const Icon(Icons.notifications_none_rounded),
                      )
                    : const Icon(Icons.notifications_none_rounded),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            24 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            const _WelcomeCard(),
            const SizedBox(height: 16),
            if (purchase != null) ...[
              Card(
                child: ListTile(
                  leading: const Icon(Icons.card_membership_rounded),
                  title: Text(purchase.packageName),
                  subtitle: Text(
                    purchase.isPending
                        ? 'Pending payment verification'
                        : purchase.statusLabel,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(AppRoutes.clientMembership),
                ),
              ),
              const SizedBox(height: 12),
            ],
            const _MembershipActions(),
            const SizedBox(height: 20),
            const Text(
              'Your FitNep updates',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            const _UpdateTypesCard(),
          ],
        ),
      ),
    );
  }
}

class _MembershipActions extends StatelessWidget {
  const _MembershipActions();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('client_view_packages_button'),
            onPressed: () => context.push(AppRoutes.clientPackages),
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('Packages'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            key: const Key('client_membership_button'),
            onPressed: () => context.push(AppRoutes.clientMembership),
            icon: const Icon(Icons.card_membership_rounded),
            label: const Text('Membership'),
          ),
        ),
      ],
    );
  }
}

class _ClientAppBarTitle extends StatelessWidget {
  const _ClientAppBarTitle();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FitNepWordmark(width: 32),
        SizedBox(width: 9),
        Flexible(
          child: Text('FitNEP', maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.favorite_rounded,
            color: AppColors.textInverse,
            size: 28,
          ),
          const SizedBox(height: 18),
          Text(
            'Welcome back',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: AppColors.textInverse,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Your diet plan, messages, tasks, and payment updates are all in one place.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textInverse.withValues(alpha: 0.9),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdateTypesCard extends StatelessWidget {
  const _UpdateTypesCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: const Column(
        children: [
          _UpdateTypeRow(
            icon: Icons.restaurant_menu_rounded,
            title: 'Diet plans',
            subtitle: 'Plan assignments and nutrition updates',
          ),
          Divider(height: 25),
          _UpdateTypeRow(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Messages',
            subtitle: 'New conversations from your care team',
          ),
          Divider(height: 25),
          _UpdateTypeRow(
            icon: Icons.task_alt_rounded,
            title: 'Tasks',
            subtitle: 'Activities assigned by your dietitian',
          ),
          Divider(height: 25),
          _UpdateTypeRow(
            icon: Icons.payments_outlined,
            title: 'Payments',
            subtitle: 'Successful payment confirmations',
          ),
        ],
      ),
    );
  }
}

class _UpdateTypeRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _UpdateTypeRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.primary, size: 21),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}
