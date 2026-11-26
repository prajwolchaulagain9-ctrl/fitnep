import 'package:flutter/material.dart';

import 'app_page.dart';
import 'fitnep_wordmark.dart';

class AppStartupView extends StatelessWidget {
  const AppStartupView({super.key, this.onRetry, this.recoveryAction});

  final VoidCallback? onRetry;
  final Widget? recoveryAction;

  @override
  Widget build(BuildContext context) {
    return AppPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Center(child: FitNepWordmark(width: 180)),
          const SizedBox(height: 32),
          if (onRetry == null) ...[
            Semantics(
              label: 'Opening FitNEP',
              child: const Center(
                child: SizedBox(width: 120, child: LinearProgressIndicator()),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              FitNepWordmark.tagline,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ] else ...[
            Text(
              'We couldn’t connect.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            const Text(
              'Please check your connection and try again.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
          if (recoveryAction case final action?) ...[
            const SizedBox(height: 12),
            action,
          ],
        ],
      ),
    );
  }
}
