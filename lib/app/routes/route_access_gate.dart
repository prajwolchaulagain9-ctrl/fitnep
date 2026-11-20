import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/services/firebase_providers.dart';
import 'app_routes.dart';
import '../../features/authentication/presentation/pages/registration_privacy_gate.dart';

enum FitNepRole {
  admin,
  dietitian,
  client,
  staff;

  static final _byName = values.asNameMap();

  static FitNepRole? fromClaim(Object? claim) =>
      claim is String ? _byName[claim.trim().toLowerCase()] : null;
}

typedef RouteSession = ({String uid, FitNepRole? role});

final _routeUserProvider = StreamProvider.autoDispose<User?>((ref) async* {
  await ref.watch(firebaseInitializationProvider.future);
  if (ref.mounted) {
    yield* ref.read(firebaseAuthProvider).idTokenChanges();
  }
});

/// Rechecks the role from Firebase's ID token when the current user or token
/// changes. The server separately verifies tokens on protected API requests.
final routeSessionProvider = FutureProvider.autoDispose<RouteSession?>((
  ref,
) async {
  final user = await ref.watch(_routeUserProvider.future);
  if (user == null) return null;
  final token = await user.getIdTokenResult();
  final role = FitNepRole.fromClaim(token.claims?['role']);
  return (uid: user.uid, role: role);
}, retry: (retryCount, error) => null);

/// Prevents route builders from exposing protected content to the wrong role.
class RouteAccessGate extends ConsumerWidget {
  const RouteAccessGate({
    required this.allowedRoles,
    required this.builder,
    this.requirePrivacyAcceptance = false,
    super.key,
  });

  final Set<FitNepRole?> allowedRoles;
  final WidgetBuilder builder;
  final bool requirePrivacyAcceptance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(routeSessionProvider)
        .when(
          skipLoadingOnRefresh: false,
          skipLoadingOnReload: false,
          loading: _loading,
          error: (error, stackTrace) => _AccessMessage(
            title: 'Access unavailable',
            message: 'FitNEP could not verify your session. Please try again.',
            onRetry: () => ref.invalidate(routeSessionProvider),
          ),
          data: (session) {
            if (session == null) {
              return const _AccessMessage(
                title: 'Sign in required',
                message: 'Sign in to access this FitNEP page.',
              );
            }
            if (!allowedRoles.contains(session.role)) {
              return const _AccessMessage(
                title: 'Access denied',
                message: 'Your account does not have access to this page.',
              );
            }
            return KeyedSubtree(
              key: ValueKey(session.uid),
              child:
                  requirePrivacyAcceptance ||
                      (session.role == FitNepRole.client &&
                          !AppConfig.useFirebaseEmulators)
                  ? RegistrationPrivacyGate(
                      uid: session.uid,
                      child: Builder(builder: builder),
                    )
                  : builder(context),
            );
          },
        );
  }

  Widget _loading() =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _AccessMessage extends StatelessWidget {
  const _AccessMessage({
    required this.title,
    required this.message,
    this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

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
              if (onRetry case final retry?)
                OutlinedButton(
                  onPressed: retry,
                  child: const Text('Try again'),
                ),
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
