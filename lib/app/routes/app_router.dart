import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/authentication/presentation/pages/password_recovery_pages.dart';
import '../../features/authentication/presentation/pages/login_page.dart';
import '../../features/authentication/presentation/pages/app_under_development_page.dart';
import '../../features/authentication/presentation/pages/signup_page.dart';
import '../../features/authentication/presentation/pages/verify_email_page.dart';
import '../../features/authentication/presentation/pages/change_staff_password_page.dart';
import '../../features/authentication/presentation/controllers/authentication_controller.dart';
import '../../features/authentication/presentation/pages/privacy_policy_page.dart';
import '../../features/authentication/presentation/pages/privacy_preferences_page.dart';
import '../../features/onboarding/presentation/pages/about_page.dart';
import '../../features/onboarding/presentation/pages/welcome_page.dart';
import '../../shared/widgets/app_page.dart';
import '../../features/admin/presentation/pages/client_list_page.dart';
import '../../features/admin/presentation/pages/client_profile_page.dart';
import '../../features/admin/presentation/pages/audit_log_page.dart';
import '../../features/admin/presentation/pages/create_package_page.dart';
import '../../features/admin/presentation/pages/edit_package_page.dart';
import '../../features/admin/presentation/pages/package_management_page.dart';
import '../../features/admin/presentation/pages/package_history_page.dart';
import '../../features/admin/presentation/pages/staff_accounts_page.dart';
import '../../features/admin/presentation/pages/staff_account_history_page.dart';
import '../../features/admin/domain/entities/package_entity.dart';
import '../../features/dashboards/presentation/pages/client_home_page.dart';
import '../../features/notifications/presentation/pages/notifications_page.dart';
import '../../features/notifications/domain/entities/notification_entity.dart';
import '../../features/notifications/presentation/pages/notification_destination_page.dart';
import '../../features/packages/presentation/pages/package_selection_page.dart';
import '../../features/packages/presentation/pages/package_approvals_page.dart';
import '../../features/purchases/presentation/pages/membership_page.dart';
import '../../features/health_assessment/presentation/pages/client_intake_page.dart';
import 'app_routes.dart';
import 'route_access_gate.dart';

final _routerRefreshProvider = Provider<_RouterRefreshNotifier>((ref) {
  final notifier = _RouterRefreshNotifier();
  ref.listen(authenticationStateProvider, (previous, next) {
    if (previous?.value?.uid != next.value?.uid) {
      ref.invalidate(routeSessionProvider);
    }
    notifier.refresh();
  });
  ref.listen(routeSessionProvider, (_, _) => notifier.refresh());
  ref.listen(staffPasswordChangeRequiredProvider, (_, _) => notifier.refresh());
  ref.onDispose(notifier.dispose);
  return notifier;
});

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = ref.watch(_routerRefreshProvider);
  final router = GoRouter(
    initialLocation: AppRoutes.adminClients,
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final authentication = ref.read(authenticationStateProvider);
      if (!authentication.hasValue) return null;

      final user = authentication.value;
      final isAuthenticated = user != null;
      final path = state.uri.path;
      final isPublicRoute = const {
        AppRoutes.welcomePath,
        AppRoutes.aboutPath,
        AppRoutes.privacyPolicyPath,
        AppRoutes.loginPath,
        AppRoutes.signupPath,
        AppRoutes.forgotPasswordPath,
        AppRoutes.resetPasswordPath,
      }.contains(path);

      if (!isAuthenticated && !isPublicRoute) {
        return AppRoutes.loginPath;
      }
      if (user != null) {
        final passwordChange = ref.read(staffPasswordChangeRequiredProvider);
        if (passwordChange.isLoading || !passwordChange.hasValue) return null;
        if (passwordChange.value == true) {
          return path == AppRoutes.changeStaffPasswordPath
              ? null
              : AppRoutes.changeStaffPasswordPath;
        }
      }
      if (isAuthenticated && !user.emailVerified) {
        // Recovery and the policy stay reachable before email verification.
        if (path != AppRoutes.verifyEmailPath &&
            path != AppRoutes.forgotPasswordPath &&
            path != AppRoutes.resetPasswordPath &&
            path != AppRoutes.privacyPolicyPath) {
          return AppRoutes.verifyEmailPath;
        }
        return null;
      }
      if (isAuthenticated &&
          (path == AppRoutes.welcomePath ||
              path == AppRoutes.loginPath ||
              path == AppRoutes.signupPath ||
              path == AppRoutes.changeStaffPasswordPath ||
              path == AppRoutes.verifyEmailPath)) {
        final session = ref.read(routeSessionProvider);
        if (session.isLoading) return null;
        return switch (session.asData?.value?.role) {
          FitNepRole.admin => AppRoutes.adminClients,
          FitNepRole.dietitian => AppRoutes.notifications,
          FitNepRole.staff => AppRoutes.appUnderDevelopmentPath,
          _ => AppRoutes.clientPackages,
        };
      }
      if (isAuthenticated && path == AppRoutes.clientHome) {
        final role = ref.read(routeSessionProvider).value?.role;
        if (role == FitNepRole.admin) return AppRoutes.adminClients;
        if (role == FitNepRole.dietitian) return AppRoutes.notifications;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.adminPackageApprovals,
        name: 'admin-package-approvals',
        builder: (context, state) => RouteAccessGate(
          requiredPermission: 'manage_business_settings',
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
        name: AppRoutes.login,
        path: AppRoutes.loginPath,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        name: AppRoutes.signup,
        path: AppRoutes.signupPath,
        builder: (context, state) => const SignupPage(),
      ),
      GoRoute(
        name: AppRoutes.changeStaffPassword,
        path: AppRoutes.changeStaffPasswordPath,
        builder: (context, state) => const ChangeStaffPasswordPage(),
      ),
      GoRoute(
        name: AppRoutes.verifyEmail,
        path: AppRoutes.verifyEmailPath,
        builder: (context, state) => const VerifyEmailPage(),
      ),
      GoRoute(
        name: AppRoutes.appUnderDevelopment,
        path: AppRoutes.appUnderDevelopmentPath,
        builder: (context, state) => RouteAccessGate(
          requiredPermission: 'view_staff_dashboard',
          builder: (_) => const AppUnderDevelopmentPage(),
        ),
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
          requiredPermission: 'view_client_dashboard',
          builder: (_) => const ClientHomePage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.clientNotifications,
        name: AppRoutes.clientNotificationsName,
        builder: (context, state) => RouteAccessGate(
          requiredPermission: 'view_own_notifications',
          builder: (_) => const NotificationsPage(),
        ),
      ),
      // Customer-facing: active packages only
      GoRoute(
        path: AppRoutes.clientPackages,
        name: AppRoutes.clientPackagesName,
        builder: (context, state) => RouteAccessGate(
          requiredPermission: 'manage_own_membership',
          builder: (_) => const PackageSelectionPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.clientMembership,
        name: AppRoutes.clientMembershipName,
        builder: (context, state) => RouteAccessGate(
          requiredPermission: 'manage_own_membership',
          builder: (_) => const MembershipPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.clientPrivacyPreferences,
        name: 'client-privacy-preferences',
        builder: (context, state) => RouteAccessGate(
          requiredPermission: 'manage_own_privacy',
          builder: (_) => const PrivacyPreferencesPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        name: 'notifications',
        builder: (context, state) => RouteAccessGate(
          requiredPermission: 'view_own_notifications',
          builder: (_) => const NotificationsPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.dietPlanDetails,
        name: AppRoutes.dietPlanDetailsName,
        builder: (context, state) => RouteAccessGate(
          requiredPermission: 'view_own_workflow',
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
          requiredPermission: 'view_own_workflow',
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
          requiredPermission: 'view_own_workflow',
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
          requiredPermission: 'view_own_workflow',
          builder: (_) => NotificationDestinationPage(
            type: NotificationType.payment,
            referenceId: state.pathParameters['id']!,
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.dietitianAssignedClient,
        name: AppRoutes.dietitianAssignedClientName,
        builder: (context, state) => RouteAccessGate(
          requiredPermission: 'view_assigned_client_records',
          builder: (_) => NotificationDestinationPage(
            type: NotificationType.assignment,
            referenceId: state.pathParameters['id']!,
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.dietitianClientIntake,
        name: AppRoutes.dietitianClientIntakeName,
        builder: (context, state) => RouteAccessGate(
          requiredPermission: 'view_assigned_client_records',
          builder: (_) =>
              ClientIntakePage(clientId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: AppRoutes.adminStaffAccounts,
        builder: (context, state) => RouteAccessGate(
          requiredPermission: 'manage_staff_accounts',
          builder: (_) => const StaffAccountsPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.adminStaffHistory,
        builder: (context, state) => RouteAccessGate(
          requiredPermission: 'manage_staff_accounts',
          builder: (_) => const StaffAccountHistoryPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.adminClients,
        name: 'admin-clients',
        builder: (context, state) => RouteAccessGate(
          requiredPermission: 'manage_client_accounts',
          builder: (_) => const ClientListPage(),
        ),
        routes: [
          GoRoute(
            path: ':id',
            name: 'client-profile',

            builder: (context, state) {
              final clientId = state.pathParameters['id']!;
              return RouteAccessGate(
                requiredPermission: 'manage_client_accounts',
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
          requiredPermission: 'view_audit_logs',
          builder: (_) => const AuditLogPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.adminPackages,
        name: 'admin-packages',
        builder: (context, state) => RouteAccessGate(
          requiredPermission: 'manage_business_settings',
          builder: (_) => const PackageManagementPage(),
        ),
        routes: [
          GoRoute(
            path: 'history',
            name: 'admin-package-history',
            builder: (context, state) => RouteAccessGate(
              requiredPermission: 'manage_business_settings',
              builder: (_) => const PackageHistoryPage(),
            ),
          ),
          GoRoute(
            path: 'create',
            name: 'admin-create-package',
            builder: (context, state) => RouteAccessGate(
              requiredPermission: 'manage_business_settings',
              builder: (_) => const CreatePackagePage(),
            ),
          ),
          GoRoute(
            path: ':packageId/edit',
            name: 'admin-edit-package',
            builder: (context, state) => RouteAccessGate(
              requiredPermission: 'manage_business_settings',
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

class _RouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}
