import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/firebase_providers.dart';
import '../features/authentication/presentation/controllers/authentication_controller.dart';
import '../features/authentication/presentation/password_reset_session_observer.dart';
import '../features/authentication/presentation/hosted_session_gate.dart';
import '../features/authentication/presentation/sign_out_to_welcome.dart';
import '../shared/widgets/app_startup_view.dart';
import 'routes/app_router.dart';
import 'theme/app_theme.dart';

final _messengerKey = GlobalKey<ScaffoldMessengerState>();

class FitNepApp extends ConsumerWidget {
  const FitNepApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(authenticationControllerProvider, (previous, next) {
      if (next.noticeMessage != null &&
          next.noticeMessage != previous?.noticeMessage) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _messengerKey.currentState?.showSnackBar(
            SnackBar(content: Text(next.noticeMessage!)),
          );
        });
      }
    });
    final authenticationBootstrap = ref.watch(authenticationBootstrapProvider);
    final authenticationState = ref.watch(authenticationStateProvider);
    final passwordChange = ref.watch(staffPasswordChangeRequiredProvider);
    final signedIn = authenticationState.value != null;
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'FitNEP',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _messengerKey,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // The supplied Figma screens define the app's light appearance.
      themeMode: ThemeMode.light,
      routerConfig: router,
      builder: (context, child) {
        final switchAccount = signedIn
            ? Consumer(
                builder: (context, ref, _) {
                  final action = ref.watch(authenticationControllerProvider);
                  return Column(
                    children: [
                      TextButton(
                        onPressed: action.isLoading
                            ? null
                            : () => signOutToWelcome(
                                context,
                                ref,
                                router: router,
                              ),
                        child: Text(
                          action.isLoading
                              ? 'Please wait…'
                              : 'Use another account',
                        ),
                      ),
                      if (action.errorMessage case final error?)
                        Text(error, textAlign: TextAlign.center),
                    ],
                  );
                },
              )
            : null;
        if (authenticationBootstrap.isLoading ||
            authenticationState.isLoading) {
          return AppStartupView(recoveryAction: switchAccount);
        }
        if (authenticationBootstrap.hasError || authenticationState.hasError) {
          return AppStartupView(
            recoveryAction: switchAccount,
            onRetry: () {
              ref.invalidate(firebaseInitializationProvider);
              ref.invalidate(authenticationBootstrapProvider);
              ref.invalidate(authenticationStateProvider);
              ref.invalidate(staffPasswordChangeRequiredProvider);
            },
          );
        }
        return PasswordResetSessionObserver(
          child: HostedSessionObserver(
            child:
                signedIn &&
                    (passwordChange.isLoading || passwordChange.hasError)
                ? Scaffold(
                    body: SafeArea(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (passwordChange.isLoading)
                                const CircularProgressIndicator(),
                              const SizedBox(height: 16),
                              Text(
                                passwordChange.hasError
                                    ? 'We couldn’t connect.'
                                    : 'Checking your account…',
                              ),
                              if (passwordChange.hasError)
                                TextButton(
                                  onPressed: () => ref.invalidate(
                                    staffPasswordChangeRequiredProvider,
                                  ),
                                  child: const Text('Try again'),
                                ),
                              ?switchAccount,
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                : child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
