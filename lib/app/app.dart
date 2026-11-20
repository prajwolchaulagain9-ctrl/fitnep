import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/firebase_providers.dart';
import '../features/authentication/presentation/controllers/authentication_controller.dart';
import '../features/authentication/presentation/password_reset_session_observer.dart';
import '../shared/widgets/app_startup_view.dart';
import 'routes/app_router.dart';
import 'theme/app_theme.dart';

class FitNepApp extends ConsumerWidget {
  const FitNepApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authenticationBootstrap = ref.watch(authenticationBootstrapProvider);
    final authenticationState = ref.watch(authenticationStateProvider);

    return MaterialApp.router(
      title: 'FitNEP',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: ref.watch(appRouterProvider),
      builder: (context, child) {
        if (authenticationBootstrap.isLoading ||
            authenticationState.isLoading) {
          return const AppStartupView();
        }
        if (authenticationBootstrap.hasError || authenticationState.hasError) {
          return AppStartupView(
            onRetry: () {
              ref.invalidate(firebaseInitializationProvider);
              ref.invalidate(authenticationBootstrapProvider);
              ref.invalidate(authenticationStateProvider);
            },
          );
        }
        return PasswordResetSessionObserver(
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
