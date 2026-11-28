import '../../../shared/widgets/wellness_illustration.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes/app_routes.dart';
import '../../../shared/widgets/fitnep_wordmark.dart';
import '../../authorization/role_home_page.dart';
import '../../health_assessment/data/client_intake_remote_datasource.dart';
import '../../health_assessment/client_intake_controller.dart';
import '../../notifications/notification_controller.dart';
import '../../onboarding/data/client_onboarding_status.dart';
import '../../packages/membership_controller.dart';

class ClientHomePage extends ConsumerWidget {
  static const notificationButtonKey = Key('client_notification_button');
  static const notificationBadgeKey = Key('client_notification_badge');

  const ClientHomePage({required this.clientId, super.key});

  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(unreadNotificationCountProvider);
    final purchase = ref.watch(membershipControllerProvider).purchase;
    final showOnboarding =
        ref.watch(clientOnboardingStatusProvider(clientId)).value ==
        ClientOnboardingStatus.skipped;
    final intake = ref.watch(ownClientIntakeProvider(clientId));
    final intakeError = intake.error;
    final showIntake =
        !intake.isLoading &&
        !intake.hasValue &&
        intakeError is ClientIntakeException &&
        intakeError.failure == ClientIntakeFailure.notFound;

    return Scaffold(
      drawer: const RoleNavigationDrawer(),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        titleSpacing: 16,
        title: const _ClientAppBarTitle(),
        actions: [
          IconButton(
            tooltip: 'Privacy preferences',
            onPressed: () => context.push(AppRoutes.clientPrivacyPreferences),
            icon: const Icon(Icons.privacy_tip_outlined),
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
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        textColor: Theme.of(context).colorScheme.onPrimary,
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
                        ? 'Payment needed or under review'
                        : purchase.statusLabel,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(AppRoutes.clientMembership),
                ),
              ),
              const SizedBox(height: 12),
            ],
            const _MembershipActions(),
            if (showOnboarding) ...[
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.monitor_weight_outlined),
                  title: const Text('Finish onboarding'),
                  subtitle: const Text(
                    'Add your height and weight to see your BMI',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () =>
                      context.pushNamed(AppRoutes.clientOnboardingName),
                ),
              ),
            ],
            if (showIntake) ...[
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.assignment_outlined),
                  title: const Text('Health intake'),
                  subtitle: const Text('Start or resume your intake form'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.pushNamed(AppRoutes.intakeEditorName),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              'Your FitNep updates',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        gradient: dark
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colors.surfaceContainerHighest,
                  colors.primaryContainer,
                ],
              )
            : null,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Welcome back',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const WellnessIllustration(
                scene: WellnessScene.movement,
                size: 86,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Your diet plan, messages, tasks, and payment updates are all in one place.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onPrimaryContainer,
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
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
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
              subtitle: 'Payment submissions and decisions',
            ),
          ],
        ),
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
        SizedBox(
          width: 36,
          child: Icon(icon, color: Theme.of(context).colorScheme.primary),
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
