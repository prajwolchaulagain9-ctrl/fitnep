import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/services/firebase_providers.dart';
import 'app_routes.dart';

/// Emits the role from Firebase's verified ID token whenever auth changes.
///
/// Firebase initialization is awaited before the auth provider is read because
/// the app creates its router while the startup screen is still visible.
final authenticatedRoleProvider = StreamProvider.autoDispose<String?>((ref) {
  final initialized = ref.watch(firebaseInitializationProvider.future);
  return _rolesAfterInitialization(
    initialized,
    () => ref.read(firebaseAuthProvider),
  );
});

Stream<String?> _rolesAfterInitialization(
  Future<void> initialized,
  FirebaseAuth Function() auth,
) async* {
  await initialized;
  await for (final user in auth().idTokenChanges()) {
    if (user == null) {
      yield null;
      continue;
    }

    final token = await user.getIdTokenResult();
    final role = token.claims?['role'];
    yield role is String ? role.trim().toLowerCase() : null;
  }
}

/// Prevents route builders from exposing protected content to the wrong role.
class RouteAccessGate extends ConsumerWidget {
  const RouteAccessGate({
    required this.allowedRoles,
    required this.builder,
    super.key,
  });

  /// An empty set means any authenticated FitNEP role is allowed.
  final Set<String> allowedRoles;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initialization = ref.watch(firebaseInitializationProvider);
    return initialization.when(
      loading: _loading,
      error: (error, stackTrace) => const _AccessMessage(
        title: 'Access unavailable',
        message: 'FitNEP could not verify your session. Please try again.',
      ),
      data: (_) => ref
          .watch(authenticatedRoleProvider)
          .when(
            loading: _loading,
            error: (error, stackTrace) => const _AccessMessage(
              title: 'Access unavailable',
              message:
                  'FitNEP could not verify your session. Please try again.',
            ),
            data: (role) {
              if (role == null) {
                return const _AccessMessage(
                  title: 'Sign in required',
                  message: 'Sign in to access this FitNEP page.',
                );
              }
              if (allowedRoles.isNotEmpty && !allowedRoles.contains(role)) {
                return const _AccessMessage(
                  title: 'Access denied',
                  message: 'Your account does not have access to this page.',
                );
              }
              return builder(context);
            },
          ),
    );
  }

  Widget _loading() =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _AccessMessage extends StatelessWidget {
  const _AccessMessage({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('FitNEP')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text(message),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => context.go(
                  AppConfig.useFirebaseEmulators
                      ? AppRoutes.demoEntry
                      : AppRoutes.welcomePath,
                ),
                child: const Text('Back to FitNEP'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
