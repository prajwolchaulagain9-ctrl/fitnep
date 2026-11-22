import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/firebase_providers.dart';
import '../features/authentication/presentation/controllers/authentication_controller.dart';
import '../features/authentication/presentation/password_reset_session_observer.dart';
import '../features/authentication/presentation/hosted_session_gate.dart';
import '../shared/widgets/app_startup_view.dart';
import 'routes/app_router.dart';
import 'theme/app_theme.dart';

class FitNepApp extends ConsumerWidget {
  const FitNepApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authenticationBootstrap = ref.watch(authenticationBootstrapProvider);
    final authenticationState = ref.watch(authenticationStateProvider);
    final passwordChange = ref.watch(staffPasswordChangeRequiredProvider);
    final signedIn = authenticationState.value != null;

    return MaterialApp.router(
      title: 'FitNEP',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // The supplied Figma screens define the app's light appearance.
      themeMode: ThemeMode.light,
      routerConfig: ref.watch(appRouterProvider),
      builder: (context, child) {
        if (authenticationBootstrap.isLoading ||
            authenticationState.isLoading ||
            (signedIn && passwordChange.isLoading)) {
          return const AppStartupView();
        }
        if (authenticationBootstrap.hasError ||
            authenticationState.hasError ||
            (signedIn && passwordChange.hasError)) {
          return AppStartupView(
            onRetry: () {
              ref.invalidate(firebaseInitializationProvider);
              ref.invalidate(authenticationBootstrapProvider);
              ref.invalidate(authenticationStateProvider);
              ref.invalidate(staffPasswordChangeRequiredProvider);
            },
          );
        }
        return PasswordResetSessionObserver(
          child: HostedSessionObserver(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}
