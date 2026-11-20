import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/authentication/presentation/pages/password_recovery_pages.dart';
import '../../features/authentication/presentation/pages/login_page.dart';
import '../../features/authentication/presentation/pages/signup_page.dart';
import '../../features/authentication/presentation/pages/verify_email_page.dart';
import '../../features/authentication/presentation/controllers/authentication_controller.dart';
import '../../features/authentication/presentation/pages/app_under_development_page.dart';
import '../../features/authentication/presentation/pages/privacy_preferences_page.dart';
import '../../features/onboarding/presentation/pages/about_page.dart';
import '../../features/onboarding/presentation/pages/welcome_page.dart';
import '../../shared/widgets/app_page.dart';
import '../../features/admin/presentation/pages/client_list_page.dart';
import '../../features/admin/presentation/pages/client_profile_page.dart';
import '../../features/admin/presentation/pages/audit_log_page.dart';
import '../../features/dashboards/presentation/pages/client_home_page.dart';
import '../../features/notifications/presentation/pages/notifications_page.dart';
import '../../features/notifications/domain/entities/notification_entity.dart';
import '../../features/notifications/presentation/pages/notification_destination_page.dart';
import 'app_routes.dart';

final _routerRefreshProvider = Provider<_RouterRefreshNotifier>((ref) {
  final notifier = _RouterRefreshNotifier();
  ref.listen(authenticationStateProvider, (_, _) => notifier.refresh());
  ref.onDispose(notifier.dispose);
  return notifier;
});

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = ref.watch(_routerRefreshProvider);
  final router = GoRouter(
    initialLocation: AppRoutes.welcomePath,
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final authentication = ref.read(authenticationStateProvider);
      if (!authentication.hasValue) return null;

      final isAuthenticated = authentication.value != null;
      final path = state.uri.path;
      final isPublicRoute = const {
        AppRoutes.welcomePath,
        AppRoutes.aboutPath,
        AppRoutes.loginPath,
        AppRoutes.signupPath,
        AppRoutes.forgotPasswordPath,
        AppRoutes.resetPasswordPath,
      }.contains(path);

      if (!isAuthenticated && !isPublicRoute) {
        return AppRoutes.loginPath;
      }
      if (isAuthenticated && ref.read(signupEmailOtpEnabledProvider)) {
        final user = authentication.value!;
        if (!user.emailVerified &&
            user.providerData.any(
              (provider) => provider.providerId == 'password',
            )) {
          // Recovery stays reachable while the email address is unverified.
          if (path != AppRoutes.verifyEmailPath &&
              path != AppRoutes.forgotPasswordPath &&
              path != AppRoutes.resetPasswordPath) {
            return AppRoutes.verifyEmailPath;
          }
          return null;
        }
      }
      if (isAuthenticated &&
          (path == AppRoutes.welcomePath ||
              path == AppRoutes.loginPath ||
              path == AppRoutes.signupPath ||
              path == AppRoutes.verifyEmailPath)) {
        return AppRoutes.appUnderDevelopmentPath;
      }
      return null;
    },
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
        builder: (context, state) => const AppUnderDevelopmentPage(),
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
          // Preserve the mode/duplicate parameters for service validation.
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
      GoRoute(
        path: AppRoutes.clientPrivacyPreferences,
        name: 'client-privacy-preferences',
        builder: (context, state) => const PrivacyPreferencesPage(),
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
