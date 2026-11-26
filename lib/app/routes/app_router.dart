import '../../features/health_assessment/presentation/pages/client_intake_page.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/authentication/presentation/pages/password_recovery_pages.dart';
import '../../features/authentication/presentation/pages/login_page.dart';
import '../../features/authentication/presentation/pages/signup_page.dart';
import '../../features/authentication/presentation/pages/verify_email_page.dart';
import '../../features/authentication/presentation/pages/change_staff_password_page.dart';
import '../../features/admin/presentation/pages/staff_accounts_page.dart';
import '../../features/admin/presentation/pages/staff_account_history_page.dart';
import '../../features/authentication/presentation/controllers/authentication_controller.dart';
import '../../features/authorization/presentation/role_home_page.dart';
import '../../features/authorization/presentation/profile_page.dart';
import '../../features/authorization/presentation/user_management_page.dart';
import '../../features/authorization/presentation/assigned_clients_page.dart';
import '../../features/authorization/presentation/client_records_page.dart';
import '../../features/authentication/presentation/pages/privacy_policy_page.dart';
import '../../features/authentication/presentation/pages/terms_and_conditions_page.dart';
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
import '../../features/notifications/presentation/controllers/notification_controller.dart';
import '../../features/notifications/presentation/controllers/notification_destination_controller.dart';
import '../../features/purchases/presentation/controllers/membership_controller.dart';
import '../../features/authentication/presentation/controllers/privacy_preferences_controller.dart';
import '../../features/admin/presentation/controllers/client_list_controller.dart';
import '../../features/admin/presentation/controllers/client_profile_controller.dart';
import '../../features/admin/presentation/controllers/audit_log_controller.dart';
import '../../features/admin/presentation/controllers/package_management_controller.dart';

final _routerRefreshProvider = Provider<_RouterRefreshNotifier>((ref) {
  final notifier = _RouterRefreshNotifier();
  ref.listen(authenticationStateProvider, (_, _) => notifier.refresh());
  ref.listen(staffPasswordChangeRequiredProvider, (_, _) => notifier.refresh());
  ref.listen(routeSessionProvider, (previous, next) {
    if (next.hasValue && !next.isLoading) {
      final session = next.value;
      if (notifier.lastSession != session) {
        if (notifier.lastSession?.role != null &&
            session?.role != null &&
            notifier.lastSession!.role != session!.role) {
          notifier.roleChanged = true;
        }
        // Clear data left by a previous identity/role before a new page mounts.
        if (notifier.lastSession != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            notifier.navigatorKey.currentState?.popUntil(
              (route) => route.isFirst,
            );
          });
        }
        ref.invalidate(notificationControllerProvider);
        ref.invalidate(notificationDestinationProvider);
        ref.invalidate(membershipControllerProvider);
        ref.invalidate(activePackagesProvider);
        ref.invalidate(packageManagementControllerProvider);
        ref.invalidate(privacyPreferencesControllerProvider);
        ref.invalidate(clientListControllerProvider);
        ref.invalidate(clientProfileControllerProvider);
        ref.invalidate(auditLogControllerProvider);
        notifier.lastSession = session;
      }
    }
    notifier.refresh();
  });
  ref.onDispose(notifier.dispose);
  return notifier;
});

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = ref.watch(_routerRefreshProvider);
  final router = GoRouter(
    navigatorKey: refreshNotifier.navigatorKey,
    initialLocation: AppConfig.useFirebaseEmulators
        ? AppRoutes.adminClients
        : AppRoutes.welcomePath,
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      if (ref.read(authenticationControllerProvider).isLoading) return null;
      final authentication = ref.read(authenticationStateProvider);
      if (!authentication.hasValue) return null;

      final isAuthenticated = authentication.value != null;
      final path = state.uri.path;
      final isPublicRoute = const {
        AppRoutes.welcomePath,
        AppRoutes.aboutPath,
        AppRoutes.privacyPolicyPath,
        AppRoutes.termsPath,
        AppRoutes.loginPath,
        AppRoutes.signupPath,
        AppRoutes.forgotPasswordPath,
        AppRoutes.resetPasswordPath,
        if (AppConfig.useFirebaseEmulators) AppRoutes.demoEntry,
      }.contains(path);

      if (!isAuthenticated && !isPublicRoute) {
        return AppConfig.useFirebaseEmulators
            ? AppRoutes.demoEntry
            : AppRoutes.loginPath;
      }
      if (isAuthenticated) {
        final change = ref.read(staffPasswordChangeRequiredProvider);
        if (change.isLoading) return null;
        if (change.value == true) {
          return path == AppRoutes.changeStaffPasswordPath
              ? null
              : AppRoutes.changeStaffPasswordPath;
        }
      }
      if (isAuthenticated && !AppConfig.useFirebaseEmulators) {
        final user = authentication.value!;
        if (!user.emailVerified &&
            user.providerData.any(
              (provider) => provider.providerId == 'password',
            )) {
          // Recovery and the policy stay reachable before email verification.
          if (path != AppRoutes.verifyEmailPath &&
              path != AppRoutes.forgotPasswordPath &&
              path != AppRoutes.resetPasswordPath &&
              path != AppRoutes.privacyPolicyPath &&
              path != AppRoutes.termsPath) {
            return AppRoutes.verifyEmailPath;
          }
          return null;
        }
      }
      if (isAuthenticated &&
          (path == AppRoutes.welcomePath ||
              path == AppRoutes.loginPath ||
              path == AppRoutes.signupPath ||
              (path == AppRoutes.changeStaffPasswordPath &&
                  state.uri.queryParameters['recover'] != 'google') ||
              path == AppRoutes.verifyEmailPath)) {
        return AppRoutes.dashboard;
      }
      final session = ref.read(routeSessionProvider).value;
      if (isAuthenticated && session?.role != null) {
        final home = dashboardForRole(session!.role!);
        final permission = permissionForRoute(path);
        if (refreshNotifier.roleChanged) {
          refreshNotifier.roleChanged = false;
          if (permission != null &&
              !AuthorizationService(session.role).hasPermission(permission)) {
            return home;
          }
        }
        if (path == AppRoutes.dashboard ||
            path == AppRoutes.appUnderDevelopmentPath) {
          return session.role == FitNepRole.client
              ? AppRoutes.clientPackages
              : home;
        }
        if (permission != null &&
            !AuthorizationService(session.role).hasPermission(permission)) {
          return '${AppRoutes.accessDenied}?permission=${Uri.encodeQueryComponent(permission)}';
        }
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.changeStaffPasswordPath,
        name: AppRoutes.changeStaffPassword,
        builder: (_, _) => const ChangeStaffPasswordPage(),
      ),
      GoRoute(
        path: AppRoutes.dietitianClientIntake,
        name: AppRoutes.dietitianClientIntakeName,
        builder: (context, state) => RouteAccessGate(
          requiredPermission: 'view_assigned_client_records',
          builder: (_) => ClientIntakePage(
            clientId: state.pathParameters['id']!,
            viewerId: ref.read(routeSessionProvider).requireValue!.uid,
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.clientIntake,
        name: AppRoutes.clientIntakeName,
        builder: (context, state) => RouteAccessGate(
          requiredPermission: 'view_client_dashboard',
          builder: (_) => ClientIntakePage(
            clientId: ref.read(routeSessionProvider).requireValue!.uid,
            viewerId: ref.read(routeSessionProvider).requireValue!.uid,
            readOnly: true,
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.adminStaffAccounts,
        builder: (_, _) => RouteAccessGate(
          requiredPermission: 'manage_staff_accounts',
          builder: (_) => const StaffAccountsPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.adminStaffHistory,
        builder: (_, _) => RouteAccessGate(
          requiredPermission: 'manage_staff_accounts',
          builder: (_) => const StaffAccountHistoryPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.accessDenied,
        builder: (context, state) => AccessDeniedPage(
          permission:
              state.uri.queryParameters['permission'] ?? 'view_admin_dashboard',
        ),
      ),
      for (final path in [
        AppRoutes.dashboard,
        AppRoutes.staffHome,
        AppRoutes.dietitianHome,
        AppRoutes.adminHome,
      ])
        GoRoute(
          path: path,
          builder: (context, state) => RouteAccessGate(
            requiredPermission: permissionForRoute(state.uri.path)!,
            builder: (_) => RoleHomePage(
              role: ref.read(routeSessionProvider).requireValue!.role!,
            ),
          ),
        ),
      GoRoute(
        path: AppRoutes.ownProfile,
        builder: (context, state) => RouteAccessGate(
          requiredPermission: 'view_own_profile',
          builder: (_) => const ProfilePage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.adminUsers,
        builder: (context, state) => RouteAccessGate(
          requiredPermission: 'manage_user_roles',
          builder: (_) => const UserManagementPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.assignedClients,
        builder: (context, state) => RouteAccessGate(
          requiredPermission: 'view_assigned_clients',
          builder: (_) => const AssignedClientsPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.clientRecords,
        builder: (context, state) => RouteAccessGate(
          requiredPermission: 'view_own_client_records',
          builder: (_) => ClientRecordsPage(
            clientId: ref.read(routeSessionProvider).requireValue!.uid,
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.assignedClientRecords,
        name: AppRoutes.assignedClientRecordsName,
        builder: (context, state) => RouteAccessGate(
          requiredPermission: 'view_assigned_client_records',
          builder: (_) =>
              ClientRecordsPage(clientId: state.pathParameters['id']!),
        ),
      ),
      if (AppConfig.useFirebaseEmulators)
        GoRoute(
          path: AppRoutes.demoEntry,
          builder: (context, state) => const DemoEntryPage(),
        ),
      GoRoute(
        path: AppRoutes.adminPackageApprovals,
        name: 'admin-package-approvals',
        builder: (context, state) => RouteAccessGate(
          requiredPermission: permissionForRoute(state.uri.path)!,
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
        name: AppRoutes.verifyEmail,
        path: AppRoutes.verifyEmailPath,
        builder: (context, state) => const VerifyEmailPage(),
      ),
      GoRoute(
        name: AppRoutes.appUnderDevelopment,
        path: AppRoutes.appUnderDevelopmentPath,
        redirect: (context, state) => AppRoutes.dashboard,
      ),
      GoRoute(
        name: AppRoutes.privacyPolicy,
        path: AppRoutes.privacyPolicyPath,
        builder: (context, state) => PrivacyPolicyPage(
          key: ValueKey(state.uri.toString()),
          anchor: state.uri.fragment,
        ),
      ),
      GoRoute(
        path: AppRoutes.termsPath,
        builder: (context, state) => TermsAndConditionsPage(
          key: ValueKey(state.uri.toString()),
          anchor: state.uri.fragment,
        ),
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
          requiredPermission: permissionForRoute(state.uri.path)!,
          builder: (_) => const ClientHomePage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.clientNotifications,
        name: AppRoutes.clientNotificationsName,
        builder: (context, state) => RouteAccessGate(
          requiredPermission: permissionForRoute(state.uri.path)!,
          builder: (_) => const NotificationsPage(),
        ),
      ),
      // Customer-facing: active packages only
      GoRoute(
        path: AppRoutes.clientPackages,
        name: AppRoutes.clientPackagesName,
        builder: (context, state) => RouteAccessGate(
          requiredPermission: permissionForRoute(state.uri.path)!,
          builder: (_) => AppConfig.useFirebaseEmulators
              ? const PackagesPage()
              : const PackageSelectionPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.clientMembership,
        name: AppRoutes.clientMembershipName,
        builder: (context, state) => RouteAccessGate(
          requiredPermission: permissionForRoute(state.uri.path)!,
          builder: (_) => const MembershipPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.clientPrivacyPreferences,
        name: 'client-privacy-preferences',
        builder: (context, state) => RouteAccessGate(
          requiredPermission: permissionForRoute(state.uri.path)!,
          builder: (_) => const PrivacyPreferencesPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        name: 'notifications',
        builder: (context, state) => RouteAccessGate(
          requiredPermission: permissionForRoute(state.uri.path)!,
          builder: (_) => const NotificationsPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.dietPlanDetails,
        name: AppRoutes.dietPlanDetailsName,
        builder: (context, state) => RouteAccessGate(
          requiredPermission: permissionForRoute(state.uri.path)!,
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
          requiredPermission: permissionForRoute(state.uri.path)!,
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
          requiredPermission: permissionForRoute(state.uri.path)!,
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
          requiredPermission: permissionForRoute(state.uri.path)!,
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
        path: AppRoutes.adminClients,
        name: 'admin-clients',
        builder: (context, state) => RouteAccessGate(
          requiredPermission: permissionForRoute(state.uri.path)!,
          builder: (_) => const ClientListPage(),
        ),
        routes: [
          GoRoute(
            path: ':id',
            name: 'client-profile',

            builder: (context, state) {
              final clientId = state.pathParameters['id']!;
              return RouteAccessGate(
                requiredPermission: permissionForRoute(state.uri.path)!,
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
          requiredPermission: permissionForRoute(state.uri.path)!,
          builder: (_) => const AuditLogPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.adminPackages,
        name: 'admin-packages',
        builder: (context, state) => RouteAccessGate(
          requiredPermission: permissionForRoute(state.uri.path)!,
          builder: (_) => const PackageManagementPage(),
        ),
        routes: [
          GoRoute(
            path: 'history',
            name: 'admin-package-history',
            builder: (context, state) => RouteAccessGate(
              requiredPermission: permissionForRoute(state.uri.path)!,
              builder: (_) => const PackageHistoryPage(),
            ),
          ),
          GoRoute(
            path: 'create',
            name: 'admin-create-package',
            builder: (context, state) => RouteAccessGate(
              requiredPermission: permissionForRoute(state.uri.path)!,
              builder: (_) => const CreatePackagePage(),
            ),
          ),
          GoRoute(
            path: ':packageId/edit',
            name: 'admin-edit-package',
            builder: (context, state) => RouteAccessGate(
              requiredPermission: permissionForRoute(state.uri.path)!,
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
  final navigatorKey = GlobalKey<NavigatorState>();
  RouteSession? lastSession;
  bool roleChanged = false;
  void refresh() => notifyListeners();
}
