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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FitNepWordmark(),
          const SizedBox(height: 56),
          Text(
            'NUTRITION & FITNESS',
            style: theme.textTheme.labelLarge?.copyWith(
              letterSpacing: 2,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Build better habits.\nTogether.',
            style: theme.textTheme.headlineLarge,
          ),
          const SizedBox(height: 24),
          Text(
            'A shared space for your nutrition, your goals and your FitNEP team.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 40),
          FilledButton(
            onPressed: () => context.pushNamed(AppRoutes.about),
            child: const Text('Learn about FitNEP'),
          ),
        ],
      ),
    );
  }
}
