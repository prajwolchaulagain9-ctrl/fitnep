import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/authorization/role_permissions.dart';
import '../../core/authorization/authorization_refresh.dart';
import '../../features/authorization/data/authorization_repository.dart';
import '../../features/authorization/domain/account.dart';
import '../../features/authorization/presentation/account_session.dart';
import '../../features/authentication/presentation/controllers/authentication_controller.dart';
import '../../features/authentication/presentation/pages/registration_privacy_gate.dart';
import '../../features/authentication/presentation/hosted_session_gate.dart';
export '../../core/authorization/role_permissions.dart';
import 'app_routes.dart';

typedef RouteSession = ({String uid, FitNepRole? role});

/// Rechecks the live server-owned account whenever its Firestore record changes.
final routeSessionProvider = FutureProvider.autoDispose<RouteSession?>((
  ref,
) async {
  final state = ref.watch(accountSessionProvider);
  if (state.hasError) throw state.error!;
  final account = state.isLoading
      ? await ref.watch(accountSessionProvider.future)
      : state.requireValue;
  if (account == null) {
    final user = ref.read(authenticationStateProvider).value;
    return user == null ? null : (uid: user.uid, role: null);
  }
  return (uid: account.id, role: account.isActive ? account.role : null);
}, retry: (retryCount, error) => null);

/// Prevents route builders from exposing protected content to the wrong role.
class RouteAccessGate extends ConsumerWidget {
  const RouteAccessGate({
    required this.requiredPermission,
    required this.builder,
    super.key,
  });

  final String requiredPermission;
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
            message: error is AuthorizationFailure
                ? error.message
                : 'FitNEP could not verify your session. Please try again.',
            onRetry: () {
              ref.invalidate(accountSessionProvider);
              ref.invalidate(routeSessionProvider);
            },
          ),
          data: (session) {
            if (session == null) {
              return const _AccessMessage(
                title: 'Sign in required',
                message: 'Sign in to access this FitNEP page.',
              );
            }
            if (!AuthorizationService(session.role)
                .hasPermission(requiredPermission)) {
              return AccessDeniedPage(permission: requiredPermission);
            }
            Widget child = KeyedSubtree(
              key: ValueKey((
                session.uid,
                session.role,
                ref.watch(authorizationEpochProvider),
              )),
              child: builder(context),
            );
            if (AppConfig.hostedSessionsEnabled) {
              child = HostedSessionGate(uid: session.uid, child: child);
              if (session.role == FitNepRole.client) {
                child = RegistrationPrivacyGate(uid: session.uid, child: child);
              }
            }
            return child;
          },
        );
  }

  Widget _loading() =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _AccessMessage extends ConsumerWidget {
  const _AccessMessage({
    required this.title,
    required this.message,
    this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
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
                      : AppRoutes.dashboard,
                ),
                child: const Text('Back to FitNEP'),
              ),
              if (ref.watch(authenticationStateProvider).value != null)
                TextButton(
                  onPressed: () => ref
                      .read(authenticationControllerProvider.notifier)
                      .signOut(),
                  child: const Text('Logout'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class AccessDeniedPage extends ConsumerStatefulWidget {
  const AccessDeniedPage({required this.permission, super.key});
  final String permission;
  @override
  ConsumerState<AccessDeniedPage> createState() => _AccessDeniedPageState();
}

class _AccessDeniedPageState extends ConsumerState<AccessDeniedPage> {
  @override
  void initState() {
    super.initState();
    // The server checks the attempted permission itself and writes DENIED.
    // Flutter cannot forge an audit result or actor.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await ref
            .read(authorizationRepositoryProvider)
            .checkPermission(widget.permission);
      } catch (_) {
        /* The visible denial remains clear even during an outage. */
      }
    });
  }

  @override
  Widget build(BuildContext context) => const _AccessMessage(
    title: 'Access denied',
    message: 'You do not have permission to access this feature.',
  );
}
