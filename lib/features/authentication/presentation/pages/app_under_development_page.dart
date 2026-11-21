import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/app_routes.dart';
import '../../../../app/routes/route_access_gate.dart';
import '../../../../app/theme/app_theme.dart';
import '../controllers/authentication_controller.dart';
import '../sign_out_to_welcome.dart';
import 'password_recovery_pages.dart';

class AppUnderDevelopmentPage extends ConsumerWidget {
  const AppUnderDevelopmentPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(authenticationControllerProvider);
    final session = ref.watch(routeSessionProvider).value;
    final canManageSharing =
        session != null &&
        (session.role == null || session.role == FitNepRole.client);

    return RecoveryPage(
      showBackButton: false,
      title: 'App Under Development',
      description:
          'We\u2019re building the complete FITNEP experience with care.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (action.errorMessage != null)
            RecoveryMessage(action.errorMessage!),
          Center(
            child: Container(
              width: 104,
              height: 104,
              decoration: const BoxDecoration(
                color: AppColors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.construction_rounded,
                color: AppColors.primary,
                size: 52,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Coming Soon',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your personalized nutrition and fitness workspace is on the way. '
            'Thank you for being part of FITNEP.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          if (session?.role == FitNepRole.admin) ...[
            OutlinedButton(
              onPressed: action.isLoading
                  ? null
                  : () => context.push(AppRoutes.adminStaffAccounts),
              child: const Text('Manage staff accounts'),
            ),
            const SizedBox(height: 12),
          ],
          if (canManageSharing) ...[
            OutlinedButton(
              onPressed: action.isLoading
                  ? null
                  : () => context.push(AppRoutes.clientPrivacyPreferences),
              child: const Text('Privacy preferences'),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton.icon(
            onPressed: action.isLoading
                ? null
                : () => signOutToWelcome(context, ref),
            icon: action.isLoading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout_rounded),
            label: Text(action.isLoading ? 'Logging out\u2026' : 'Logout'),
          ),
        ],
      ),
    );
  }
}
