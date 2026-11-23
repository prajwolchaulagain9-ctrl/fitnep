import 'package:fitnep/features/authentication/data/registration_privacy.dart';

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitnep/app/app.dart';
import 'package:fitnep/app/routes/app_router.dart';
import 'package:fitnep/app/routes/app_routes.dart';
import 'package:fitnep/core/services/firebase_providers.dart';
import 'package:fitnep/features/authentication/data/password_recovery_service.dart';
import 'package:fitnep/features/authentication/presentation/pages/password_recovery_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/signed_out_auth.dart';

class _UnusedAuth extends Fake implements FirebaseAuth {}

class _Recovery extends PasswordRecoveryService {
  _Recovery() : super(_UnusedAuth());
  RecoveryFailure? error;
  Completer<void>? pending;
  int requests = 0;
  int resets = 0;
  int signOuts = 0;
  String? password;

  @override
  Future<void> request(String email) async {
    requests++;
    if (pending != null) await pending!.future;
    if (error != null) throw error!;
  }

  @override
  Future<String> verify(String code) async {
    if (error != null) throw error!;
    return 'client@example.com';
  }

  @override
  Future<void> confirm(String code, String newPassword) async {
    resets++;
    if (pending != null) await pending!.future;
    if (error != null) throw error!;
    password = newPassword;
  }

  @override
  Future<void> clearLocalSession() async {
    signOuts++;
  }
}

Future<ProviderContainer> _open(
  WidgetTester tester,
  _Recovery recovery,
  String route,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        registrationAcceptedProvider.overrideWith((ref, uid) async => true),
        firebaseAuthProvider.overrideWithValue(SignedOutAuth()),
        firebaseInitializationProvider.overrideWith((ref) async {}),
        passwordRecoveryProvider.overrideWithValue(recovery),
      ],
      child: const FitNepApp(),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(FitNepApp)),
  );
  container.read(appRouterProvider).go(route);
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('cold recovery link opens after Firebase becomes ready', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        'fitnep://auth/forgot-password';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final ready = Completer<void>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          registrationAcceptedProvider.overrideWith((ref, uid) async => true),
          firebaseAuthProvider.overrideWithValue(SignedOutAuth()),
          firebaseInitializationProvider.overrideWith((ref) => ready.future),
        ],
        child: const FitNepApp(),
      ),
    );
    await tester.pump();
    expect(find.text('Send reset link'), findsNothing);
    ready.complete();
    await tester.pumpAndSettle();
    expect(find.text('Send reset link'), findsOneWidget);
  });
  testWidgets(
    'cleanup failure retries sign-out without replaying successful reset',
    (tester) async {
      final recovery = _Recovery();
      await _open(
        tester,
        recovery,
        '/reset-password?mode=resetPassword&oobCode=valid_code',
      );
      recovery.error = const RecoveryFailure(
        'Finish signing out.',
        passwordUpdated: true,
      );
      await tester.enterText(find.byType(TextFormField).at(0), 'Stronger!12');
      await tester.enterText(find.byType(TextFormField).at(1), 'Stronger!12');
      await tester.ensureVisible(find.text('Update password'));
      await tester.tap(find.text('Update password'));
      await tester.pumpAndSettle();
      expect(find.text('Password updated'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      await tester.tap(find.text('Finish signing out'));
      await tester.pumpAndSettle();
      expect(recovery.resets, 1);
      expect(recovery.signOuts, 1);
      expect(find.text('Back to login'), findsOneWidget);
    },
  );
  testWidgets('recovery routes remain gated on Firebase initialization', (
    tester,
  ) async {
    final ready = Completer<void>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          registrationAcceptedProvider.overrideWith((ref, uid) async => true),
          firebaseAuthProvider.overrideWithValue(SignedOutAuth()),
          firebaseInitializationProvider.overrideWith((ref) => ready.future),
        ],
        child: const FitNepApp(),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(FitNepApp)),
    );
    container.read(appRouterProvider).go(AppRoutes.forgotPasswordPath);
    await tester.pump();
    expect(find.text('Send reset link'), findsNothing);
    ready.complete();
    await tester.pumpAndSettle();
    expect(find.text('Send reset link'), findsOneWidget);
  });

  testWidgets('invalid email blocks submission and repeated taps send once', (
    tester,
  ) async {
    final recovery = _Recovery()..pending = Completer<void>();
    await _open(tester, recovery, AppRoutes.forgotPasswordPath);
    await tester.tap(find.text('Send reset link'));
    await tester.pump();
    expect(recovery.requests, 0);
    await tester.enterText(find.byType(TextFormField), 'client@example.com');
    await tester.tap(find.text('Send reset link'));
    await tester.pump();
    await tester.tap(find.text('Sending…'));
    expect(recovery.requests, 1);
    recovery.pending!.complete();
    await tester.pumpAndSettle();
    expect(
      find.text(PasswordRecoveryService.requestConfirmation),
      findsOneWidget,
    );
  });

  testWidgets('delivery failure shows retry and successful retry confirms', (
    tester,
  ) async {
    final recovery = _Recovery()
      ..error = const RecoveryFailure('Check your connection and try again.');
    await _open(tester, recovery, AppRoutes.forgotPasswordPath);
    await tester.enterText(find.byType(TextFormField), 'client@example.com');
    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();
    expect(find.text('Check your connection and try again.'), findsOneWidget);
    recovery.error = null;
    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();
    expect(find.text('Check your email'), findsOneWidget);
  });

  testWidgets(
    'reset validates matching passwords, clears secrets, and returns to login',
    (tester) async {
      final recovery = _Recovery();
      await _open(
        tester,
        recovery,
        '/reset-password?mode=resetPassword&oobCode=valid_code',
      );
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '  Stronger!12  ');
      await tester.enterText(fields.at(1), 'wrong');
      await tester.ensureVisible(find.text('Update password'));
      await tester.tap(find.text('Update password'));
      await tester.pump();
      expect(recovery.resets, 0);
      expect(find.text('Your passwords do not match.'), findsOneWidget);
      await tester.enterText(fields.at(1), '  Stronger!12  ');
      await tester.ensureVisible(find.text('Update password'));
      await tester.tap(find.text('Update password'));
      await tester.pumpAndSettle();
      expect(recovery.password, '  Stronger!12  ');
      expect(find.text('Password updated'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      await tester.tap(find.text('Back to login'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome back'), findsOneWidget);
    },
  );

  testWidgets('expired link offers a fresh request and no password form', (
    tester,
  ) async {
    final recovery = _Recovery()
      ..error = const RecoveryFailure('Link expired.', invalidLink: true);
    await _open(
      tester,
      recovery,
      '/reset-password?mode=resetPassword&oobCode=valid_code',
    );
    expect(find.byType(RecoveryPasswordField), findsNothing);
    await tester.tap(find.text('Request a new reset link'));
    await tester.pumpAndSettle();
    expect(find.text('Send reset link'), findsOneWidget);
  });

  testWidgets('password visibility resets after leaving and returning', (
    tester,
  ) async {
    final container = await _open(
      tester,
      _Recovery(),
      '/reset-password?mode=resetPassword&oobCode=valid_code',
    );
    await tester.tap(find.byTooltip('Show new password'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).obscureText,
      isFalse,
    );
    container.read(appRouterProvider).go(AppRoutes.forgotPasswordPath);
    await tester.pumpAndSettle();
    container
        .read(appRouterProvider)
        .go('/reset-password?mode=resetPassword&oobCode=valid_code');
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).obscureText,
      isTrue,
    );
  });

  testWidgets(
    'recovery remains usable on a small screen with keyboard and larger text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _open(tester, _Recovery(), AppRoutes.forgotPasswordPath);
      await tester.enterText(find.byType(TextFormField), 'client@example.com');
      await tester.ensureVisible(find.text('Send reset link'));
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();
      expect(find.text('Check your email'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
