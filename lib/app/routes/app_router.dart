import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/authentication/presentation/pages/password_recovery_pages.dart';
import '../../features/onboarding/presentation/pages/about_page.dart';
import '../../features/onboarding/presentation/pages/welcome_page.dart';
import '../../shared/widgets/app_page.dart';
import 'app_routes.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.welcomePath,
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
          // Preserve the mode/duplicate parameters for service validation.
          initialLink: state.uri.query.isEmpty
              ? null
              : 'fitnep://auth/reset-password?${state.uri.query}',
        ),
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
