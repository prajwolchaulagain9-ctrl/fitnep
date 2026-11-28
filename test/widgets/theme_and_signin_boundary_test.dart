import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitnep/app/app.dart';
import 'package:fitnep/app/routes/route_access_gate.dart';
import 'package:fitnep/app/theme/app_theme.dart';
import 'package:fitnep/shared/firebase_providers.dart';
import 'package:fitnep/features/authentication/data/registration_privacy.dart';
import 'package:fitnep/features/authentication/authentication_controller.dart';
import 'package:fitnep/shared/widgets/app_startup_view.dart';
import 'package:fitnep/shared/widgets/fitnep_wordmark.dart';
import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/offline_hosted_session.dart';
import '../support/memory_session_preference_store.dart';

class _Identity extends Fake implements User {
  @override
  String get uid => 'client-1';
  @override
  bool get emailVerified => true;
  @override
  List<UserInfo> get providerData => [];
}

class _Auth extends Fake implements FirebaseAuth {
  final identity = _Identity();
  @override
  User get currentUser => identity;
  @override
  Stream<User?> authStateChanges() => Stream.value(identity);
}

class _CompletingGoogleSignIn extends AuthenticationController {
  @override
  AuthenticationActionState build() =>
      const AuthenticationActionState(isLoading: true, isGoogleSignIn: true);
  void finish() => state = const AuthenticationActionState();
}

void main() {
  testWidgets(
    'Google credential refresh finishes before account checks or consent UI',
    (tester) async {
      var checks = 0;
      final preferences = MemorySessionPreferenceStore()
        ..rememberSession = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            offlineHostedSessionOverride,
            firebaseInitializationProvider.overrideWith((ref) async {}),
            firebaseAuthProvider.overrideWithValue(_Auth()),
            sessionPreferenceStoreProvider.overrideWithValue(preferences),
            authenticationControllerProvider.overrideWith(
              _CompletingGoogleSignIn.new,
            ),
            staffPasswordChangeRequiredProvider.overrideWith((ref) async {
              await ref.watch(authenticationSettledProvider.future);
              checks++;
              return false;
            }),
            routeSessionProvider.overrideWith((ref) async {
              await ref.watch(authenticationSettledProvider.future);
              return (
                uid: 'client-1',
                role: FitNepRole.client,
                auditRead: false,
                paymentsVerify: false,
              );
            }),
            registrationAcceptedProvider.overrideWith(
              (ref, uid) async => false,
            ),
          ],
          child: const FitNepApp(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(checks, 0);
      expect(find.byType(AppStartupView), findsOneWidget);
      expect(find.text('Access unavailable'), findsNothing);
      expect(find.text('Before you continue'), findsNothing);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(FitNepApp)),
      );
      (container.read(
        authenticationControllerProvider.notifier,
      ) as _CompletingGoogleSignIn).finish();
      await tester.pumpAndSettle();
      expect(checks, 1);
      expect(find.text('Before you continue'), findsOneWidget);
      expect(find.text('Access unavailable'), findsNothing);
    },
  );

  test('FitNEP palettes keep text and controls readable in both modes', () {
    expect(AppTheme.light.scaffoldBackgroundColor, const Color(0xFFF6F5F9));
    expect(AppTheme.light.colorScheme.primary, const Color(0xFF66517E));
    expect(AppTheme.dark.scaffoldBackgroundColor, const Color(0xFF24242C));
    expect(AppTheme.dark.colorScheme.primary, const Color(0xFFCBB9E4));
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return (x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05));
    }

    for (final theme in [AppTheme.light, AppTheme.dark]) {
      final c = theme.colorScheme;
      expect(contrast(c.onSurface, c.surface), greaterThanOrEqualTo(4.5));
      expect(
        contrast(c.onSurfaceVariant, c.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(contrast(c.onPrimary, c.primary), greaterThanOrEqualTo(4.5));
      expect(
        contrast(c.onPrimaryContainer, c.primaryContainer),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(c.primary, c.primaryContainer),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(c.onSurfaceVariant, theme.cardTheme.color!),
        greaterThanOrEqualTo(4.5),
      );
    }
    expect(
      contrast(AppColors.logoForeground, AppColors.logoBackground),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(AppColors.darkLogoForeground, AppColors.darkLogoBackground),
      greaterThanOrEqualTo(4.5),
    );
  });

  testWidgets('the FitNEP logo follows changes to the active theme', (
    tester,
  ) async {
    Future<void> render(ThemeData theme) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Center(child: FitNepWordmark()),
        ),
      );
      await tester.pumpAndSettle();
    }

    final logo = find.byType(FitNepWordmark);
    final filter = find.descendant(
      of: logo,
      matching: find.byType(ColorFiltered),
    );
    await render(AppTheme.light);
    expect(find.text('Your Health Partner'), findsOneWidget);
    final light = tester.widget<ColorFiltered>(filter).colorFilter;
    await render(AppTheme.dark);
    expect(find.text('Your Health Partner'), findsOneWidget);
    expect(tester.widget<ColorFiltered>(filter).colorFilter, isNot(light));
    final image = tester.widget<Image>(
      find.descendant(of: logo, matching: find.byType(Image)),
    );
    expect((image.image as AssetImage).assetName, FitNepWordmark.assetPath);
  });

  testWidgets('reduced motion removes shared-axis page movement', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('Destination')),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(SharedAxisTransition), findsNothing);
    expect(find.text('Destination'), findsOneWidget);
    await tester.pumpAndSettle();
  });
}
