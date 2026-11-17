import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/firebase_providers.dart';
import '../shared/widgets/app_startup_view.dart';
import 'routes/app_router.dart';
import 'theme/app_theme.dart';

class FitNepApp extends ConsumerWidget {
  const FitNepApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initialization = ref.watch(firebaseInitializationProvider);

    return MaterialApp.router(
      title: 'FitNEP',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: ref.watch(appRouterProvider),
      builder: (context, child) => initialization.when(
        data: (_) => child ?? const SizedBox.shrink(),
        loading: () => const AppStartupView(),
        error: (error, stackTrace) => AppStartupView(
          onRetry: () => ref.invalidate(firebaseInitializationProvider),
        ),
      ),
    );
  }
}
