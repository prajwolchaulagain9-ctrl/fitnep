import 'package:flutter/material.dart';

import 'app_page.dart';
import 'fitnep_wordmark.dart';

class AppStartupView extends StatelessWidget {
  const AppStartupView({super.key, this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return AppPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const FitNepWordmark(),
          const SizedBox(height: 32),
          if (onRetry == null) ...[
            Semantics(
              label: 'Opening FitNEP',
              child: const LinearProgressIndicator(),
            ),
            const SizedBox(height: 16),
            const Text('Getting things ready…'),
          ] else ...[
            Text(
              'We couldn’t connect.',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            const Text('Please check your connection and try again.'),
            const SizedBox(height: 24),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ],
      ),
    );
  }
}
