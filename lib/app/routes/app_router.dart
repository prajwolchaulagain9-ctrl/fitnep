import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/authentication/presentation/pages/password_recovery_pages.dart';
import '../../features/onboarding/presentation/pages/about_page.dart';
import '../../features/onboarding/presentation/pages/welcome_page.dart';
import '../../shared/widgets/app_page.dart';
import '../../features/admin/presentation/pages/client_list_page.dart';
import '../../features/admin/presentation/pages/client_profile_page.dart';
import '../../features/admin/presentation/pages/audit_log_page.dart';
import '../../features/admin/presentation/pages/create_package_page.dart';
import '../../features/admin/presentation/pages/edit_package_page.dart';
import '../../features/admin/presentation/pages/package_management_page.dart';
import '../../features/admin/domain/entities/package_entity.dart';
import '../../features/dashboards/presentation/pages/client_home_page.dart';
import '../../features/notifications/presentation/pages/notifications_page.dart';
import '../../features/notifications/domain/entities/notification_entity.dart';
import '../../features/notifications/presentation/pages/notification_destination_page.dart';
import '../../features/packages/presentation/pages/package_selection_page.dart';
import 'app_routes.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.adminClients,
    debugLogDiagnostics: false,
    routes: [
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
        builder: (context, state) => const ClientHomePage(),
      ),
      GoRoute(
        path: AppRoutes.clientNotifications,
        name: AppRoutes.clientNotificationsName,
        builder: (context, state) => const NotificationsPage(),
      ),
      // Customer-facing: active packages only
      GoRoute(
        path: AppRoutes.clientPackages,
        name: AppRoutes.clientPackagesName,
        builder: (context, state) => const PackageSelectionPage(),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        name: 'notifications',
        builder: (context, state) => const NotificationsPage(),
      ),
      GoRoute(
        path: AppRoutes.dietPlanDetails,
        name: AppRoutes.dietPlanDetailsName,
        builder: (context, state) => NotificationDestinationPage(
          type: NotificationType.dietPlan,
          referenceId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.messageThread,
        name: AppRoutes.messageThreadName,
        builder: (context, state) => NotificationDestinationPage(
          type: NotificationType.message,
          referenceId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.taskDetails,
        name: AppRoutes.taskDetailsName,
        builder: (context, state) => NotificationDestinationPage(
          type: NotificationType.task,
          referenceId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.paymentDetails,
        name: AppRoutes.paymentDetailsName,
        builder: (context, state) => NotificationDestinationPage(
          type: NotificationType.payment,
          referenceId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.adminClients,
        name: 'admin-clients',
        builder: (context, state) => const ClientListPage(),
        routes: [
          GoRoute(
            path: ':id',
            name: 'client-profile',
            builder: (context, state) {
              final clientId = state.pathParameters['id']!;
              return ClientProfilePage(clientId: clientId);
            },
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.auditLog,
        name: 'audit-log',
        builder: (context, state) => const AuditLogPage(),
      ),
      GoRoute(
        path: AppRoutes.adminPackages,
        name: 'admin-packages',
        builder: (context, state) => const PackageManagementPage(),
        routes: [
          GoRoute(
            path: 'create',
            name: 'admin-create-package',
            builder: (context, state) => const CreatePackagePage(),
          ),
          GoRoute(
            path: ':packageId/edit',
            name: 'admin-edit-package',
            builder: (context, state) {
              final package = state.extra as PackageEntity;
              return EditPackagePage(package: package);
            },
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
