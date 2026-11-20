import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/firebase_providers.dart';
import '../../features/authentication/presentation/controllers/authentication_controller.dart';
import 'app_routes.dart';

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

Future<FitNepRole?> resolveVerifiedRole(User user, FirebaseAuth auth) async {
  if (auth.currentUser?.uid != user.uid) return null;
  final token = await user.getIdTokenResult();
  if (auth.currentUser?.uid != user.uid) return null;
  final claims = token.claims ?? <String, dynamic>{};
  // Verified self-service accounts are clients. Privileged roles always come
  // from signed custom claims; the API applies the same default.
  if (!claims.containsKey('role') && claims['email_verified'] == true) {
    return FitNepRole.client;
  }
  return FitNepRole.fromClaim(claims['role']);
}

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
  final role = await resolveVerifiedRole(user, ref.read(firebaseAuthProvider));
  return (uid: user.uid, role: role);
}, retry: (retryCount, error) => null);

/// Prevents route builders from exposing protected content to the wrong role.
class RouteAccessGate extends ConsumerWidget {
  const RouteAccessGate({
    required this.allowedRoles,
    required this.builder,
    super.key,
  });

  final Set<FitNepRole> allowedRoles;
  final WidgetBuilder builder;

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
                showSignOut: false,
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
              child: builder(context),
            );
          },
        );
  }

  Widget _loading() => const Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 20),
          Text('Getting your account ready…'),
        ],
      ),
    ),
  );
}

class _AccessMessage extends ConsumerWidget {
  const _AccessMessage({
    required this.title,
    required this.message,
    this.onRetry,
    this.showSignOut = true,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;
  final bool showSignOut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(authenticationControllerProvider);
    return Scaffold(
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
                if (action.errorMessage case final error?) ...[
                  Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                FilledButton(
                  onPressed: action.isLoading
                      ? null
                      : () async {
                          if (showSignOut &&
                              !await ref
                                  .read(
                                    authenticationControllerProvider.notifier,
                                  )
                                  .signOut()) {
                            return;
                          }
                          if (context.mounted) {
                            context.go(AppRoutes.welcomePath);
                          }
                        },
                  child: Text(showSignOut ? 'Sign out' : 'Back to FitNEP'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
