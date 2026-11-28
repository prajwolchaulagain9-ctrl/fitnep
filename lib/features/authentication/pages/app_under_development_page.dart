import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../authentication_controller.dart';
import '../sign_out_to_welcome.dart';
import 'password_recovery_pages.dart';

class AppUnderDevelopmentPage extends ConsumerWidget {
  const AppUnderDevelopmentPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(authenticationControllerProvider);
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
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.construction_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 52,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Coming Soon',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your personalized nutrition and fitness workspace is on the way. '
            'Thank you for being part of FITNEP.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
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
