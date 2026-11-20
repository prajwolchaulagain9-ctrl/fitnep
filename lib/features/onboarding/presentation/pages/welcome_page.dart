import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/app_routes.dart';
import '../../../../shared/widgets/app_page.dart';
import '../../../../shared/widgets/fitnep_wordmark.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppPage(
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: FitNepWordmark()),
          const SizedBox(height: 32),
          Text(
            'NUTRITION & FITNESS',
            style: theme.textTheme.labelMedium?.copyWith(
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Build better habits.\nTogether.',
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'A shared space for your nutrition, your goals and your FitNEP team.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => context.pushNamed(AppRoutes.login),
            child: const Text('Log in'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => context.pushNamed(AppRoutes.about),
            child: const Text('Learn about FitNEP'),
          ),
        ],
      ),
    );
  }
}
