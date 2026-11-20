import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/authentication/presentation/pages/password_recovery_pages.dart';
import '../../features/authentication/presentation/pages/privacy_policy_page.dart';
import '../../features/authentication/presentation/pages/privacy_preferences_page.dart';
import '../../features/onboarding/presentation/pages/about_page.dart';
import '../../features/onboarding/presentation/pages/welcome_page.dart';
import '../../shared/widgets/app_page.dart';
import '../../features/packages/presentation/pages/packages_page.dart';
import '../../features/packages/presentation/pages/package_approvals_page.dart';
import '../../features/onboarding/presentation/pages/demo_entry_page.dart';
import '../../core/config/app_config.dart';
import '../../features/admin/presentation/pages/client_list_page.dart';
import '../../features/admin/presentation/pages/client_profile_page.dart';
import '../../features/admin/presentation/pages/audit_log_page.dart';
import '../../features/admin/presentation/pages/create_package_page.dart';
import '../../features/admin/presentation/pages/edit_package_page.dart';
import '../../features/admin/presentation/pages/package_management_page.dart';
import '../../features/admin/presentation/pages/package_history_page.dart';
import '../../features/admin/domain/entities/package_entity.dart';
import '../../features/dashboards/presentation/pages/client_home_page.dart';
import '../../features/notifications/presentation/pages/notifications_page.dart';
import '../../features/notifications/domain/entities/notification_entity.dart';
import '../../features/notifications/presentation/pages/notification_destination_page.dart';
import '../../features/packages/presentation/pages/package_selection_page.dart';
import '../../features/purchases/presentation/pages/membership_page.dart';
import 'app_routes.dart';
import 'route_access_gate.dart';

const _sharedRoles = {
  FitNepRole.client,
  FitNepRole.dietitian,
  FitNepRole.admin,
};

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: AppConfig.useFirebaseEmulators
        ? AppRoutes.demoEntry
        : AppRoutes.welcomePath,
    routes: [
      if (AppConfig.useFirebaseEmulators)
        GoRoute(
          path: AppRoutes.demoEntry,
          builder: (context, state) => const DemoEntryPage(),
        ),
      GoRoute(
        path: AppRoutes.adminPackageApprovals,
        name: 'admin-package-approvals',
        builder: (context, state) => RouteAccessGate(
          allowedRoles: const {FitNepRole.admin},
          builder: (_) => const PackageApprovalsPage(),
        ),
      ),
      GoRoute(
        name: AppRoutes.welcome,
        path: AppRoutes.welcomePath,
        builder: (context, state) => const WelcomePage(),
      ),
      GoRoute(
        name: AppRoutes.about,
        path: AppRoutes.aboutPath,
        builder: (context, state) => const AboutPage(),
      ),
      GoRoute(
        name: AppRoutes.privacyPolicy,
        path: AppRoutes.privacyPolicyPath,
        builder: (context, state) => const PrivacyPolicyPage(),
      ),
      GoRoute(
        name: AppRoutes.forgotPassword,
        path: AppRoutes.forgotPasswordPath,
        builder: (context, state) => const ForgotPasswordPage(),
      ),
      GoRoute(
        name: AppRoutes.resetPassword,
        path: AppRoutes.resetPasswordPath,
        builder: (context, state) => ResetPasswordPage(
          key: ValueKey(state.uri.toString()),
          initialLink: state.uri.query.isEmpty
              ? null
              : 'fitnep://auth/reset-password?${state.uri.query}',
        ),
      ),
      GoRoute(
        path: AppRoutes.clientHome,
        name: AppRoutes.clientHomeName,
        builder: (context, state) => RouteAccessGate(
          allowedRoles: const {FitNepRole.client},
          builder: (_) => const ClientHomePage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.clientNotifications,
        name: AppRoutes.clientNotificationsName,
        builder: (context, state) => RouteAccessGate(
          allowedRoles: const {FitNepRole.client},
          builder: (_) => const NotificationsPage(),
        ),
      ),
      // Customer-facing: active packages only
      GoRoute(
        path: AppRoutes.clientPackages,
        name: AppRoutes.clientPackagesName,
        builder: (context, state) => RouteAccessGate(
          allowedRoles: const {FitNepRole.client},
          builder: (_) => AppConfig.useFirebaseEmulators
              ? const PackagesPage()
              : const PackageSelectionPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.clientMembership,
        name: AppRoutes.clientMembershipName,
        builder: (context, state) => RouteAccessGate(
          allowedRoles: const {FitNepRole.client},
          builder: (_) => const MembershipPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.clientPrivacyPreferences,
        name: 'client-privacy-preferences',
        builder: (context, state) => RouteAccessGate(
          allowedRoles: const {FitNepRole.client},
          builder: (_) => const PrivacyPreferencesPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        name: 'notifications',
        builder: (context, state) => RouteAccessGate(
          allowedRoles: _sharedRoles,
          builder: (_) => const NotificationsPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.dietPlanDetails,
        name: AppRoutes.dietPlanDetailsName,
        builder: (context, state) => RouteAccessGate(
          allowedRoles: _sharedRoles,
          builder: (_) => NotificationDestinationPage(
            type: NotificationType.dietPlan,
            referenceId: state.pathParameters['id']!,
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.messageThread,
        name: AppRoutes.messageThreadName,
        builder: (context, state) => RouteAccessGate(
          allowedRoles: _sharedRoles,
          builder: (_) => NotificationDestinationPage(
            type: NotificationType.message,
            referenceId: state.pathParameters['id']!,
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.taskDetails,
        name: AppRoutes.taskDetailsName,
        builder: (context, state) => RouteAccessGate(
          allowedRoles: _sharedRoles,
          builder: (_) => NotificationDestinationPage(
            type: NotificationType.task,
            referenceId: state.pathParameters['id']!,
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.paymentDetails,
        name: AppRoutes.paymentDetailsName,
        builder: (context, state) => RouteAccessGate(
          allowedRoles: _sharedRoles,
          builder: (_) => NotificationDestinationPage(
            type: NotificationType.payment,
            referenceId: state.pathParameters['id']!,
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.adminClients,
        name: 'admin-clients',
        builder: (context, state) => RouteAccessGate(
          allowedRoles: const {FitNepRole.admin},
          builder: (_) => const ClientListPage(),
        ),
        routes: [
          GoRoute(
            path: ':id',
            name: 'client-profile',

            builder: (context, state) {
              final clientId = state.pathParameters['id']!;
              return RouteAccessGate(
                allowedRoles: const {FitNepRole.admin},
                builder: (_) => ClientProfilePage(clientId: clientId),
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.auditLog,
        name: 'audit-log',
        builder: (context, state) => RouteAccessGate(
          allowedRoles: const {FitNepRole.admin},
          builder: (_) => const AuditLogPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.adminPackages,
        name: 'admin-packages',
        builder: (context, state) => RouteAccessGate(
          allowedRoles: const {FitNepRole.admin},
          builder: (_) => const PackageManagementPage(),
        ),
        routes: [
          GoRoute(
            path: 'history',
            name: 'admin-package-history',
            builder: (context, state) => RouteAccessGate(
              allowedRoles: const {FitNepRole.admin},
              builder: (_) => const PackageHistoryPage(),
            ),
          ),
          GoRoute(
            path: 'create',
            name: 'admin-create-package',
            builder: (context, state) => RouteAccessGate(
              allowedRoles: const {FitNepRole.admin},
              builder: (_) => const CreatePackagePage(),
            ),
          ),
          GoRoute(
            path: ':packageId/edit',
            name: 'admin-edit-package',
            builder: (context, state) => RouteAccessGate(
              allowedRoles: const {FitNepRole.admin},
              builder: (context) {
                final package = state.extra;
                if (package is PackageEntity &&
                    package.id == state.pathParameters['packageId']) {
                  return EditPackagePage(package: package);
                }
                return AppPage(
                  title: 'Edit package',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Select a package from the list to edit it.'),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => context.go(AppRoutes.adminPackages),
                        child: const Text('Manage packages'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => AppPage(
      title: 'Page unavailable',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Let’s get you back.',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          const Text(
            'This page is not available. Return to FitNEP to continue.',
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => context.goNamed(AppRoutes.welcome),
            child: const Text('Back to FitNEP'),
          ),
        ],
      ),
    ),
  );
  ref.onDispose(router.dispose);
  return router;
});
