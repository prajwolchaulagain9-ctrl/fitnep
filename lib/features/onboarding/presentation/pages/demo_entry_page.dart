import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/app_routes.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/services/firebase_providers.dart';
import '../../../../shared/widgets/app_page.dart';
import '../../../../shared/widgets/fitnep_wordmark.dart';

class DemoEntryPage extends ConsumerStatefulWidget {
  const DemoEntryPage({super.key});
  @override
  ConsumerState<DemoEntryPage> createState() => _DemoEntryPageState();
}

class _DemoEntryPageState extends ConsumerState<DemoEntryPage> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn(String role) async {
    if (_busy || !AppConfig.useFirebaseEmulators) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = ref.read(firebaseAuthProvider);
      await auth.signOut();
      await auth.signInWithEmailAndPassword(
        email: 'demo-$role@fitnep.test',
        password: 'FitnepDemo123!',
      );
      if (!mounted) return;
      context.push(
        role == 'admin'
            ? AppRoutes.adminPackageApprovals
            : AppRoutes.clientPackages,
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'The local demo is unavailable. Start it on your laptop and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppPage(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: FitNepWordmark()),
        const SizedBox(height: 32),
        Text(
          'Try your FitNEP journey.',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        const Text('Local project demo. No real money is processed.'),
        const SizedBox(height: 24),
        if (_error != null) ...[
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 16),
        ],
        FilledButton(
          onPressed: _busy ? null : () => _signIn('client'),
          child: Text(_busy ? 'Opening…' : 'Continue as demo client'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _busy ? null : () => _signIn('admin'),
          child: const Text('Continue as demo admin'),
        ),
        const SizedBox(height: 20),
        TextButton(
          onPressed: () => context.push(AppRoutes.welcomePath),
          child: const Text('View welcome screen'),
        ),
      ],
    ),
  );
}
