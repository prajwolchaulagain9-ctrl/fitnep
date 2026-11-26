import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/app_routes.dart';
import '../../../../shared/widgets/app_page.dart';
import '../../../../shared/widgets/fitnep_wordmark.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppPage(
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.goNamed(AppRoutes.welcome);
                }
              },
              icon: const Icon(Icons.arrow_back, size: 20),
              label: const Text('Back'),
            ),
          ),
          const SizedBox(height: 16),
          const Center(child: FitNepWordmark()),
          const SizedBox(height: 32),
          Text('About FitNEP', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(FitNepWordmark.tagline, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 24),
          Text(
            'FitNEP brings clients and their nutrition team into one place, '
            'with a focus on practical plans and steady progress.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          const _Detail(
            title: 'Your goals',
            description: 'Start with what you want to achieve and the habits that fit your life.',
          ),
          const _Detail(
            title: 'Your nutrition team',
            description:
                'Dietitians and staff work together to support your program.',
          ),
          const _Detail(
            title: 'Your next step',
            description: 'A suitable package is the starting point for your FitNEP journey.',
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => context.push(AppRoutes.clientPackages),
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('View packages'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => context.push(AppRoutes.clientPrivacyPreferences),
            icon: const Icon(Icons.privacy_tip_outlined),
            label: const Text('Privacy preferences'),
          ),
          TextButton(
            onPressed: () => context.pushNamed(AppRoutes.privacyPolicy),
            child: const Text('Read the Privacy Policy'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => context.goNamed(AppRoutes.welcome),
            child: const Text('Back to welcome'),
          ),
        ],
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(description, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
