import 'dart:async';

import 'package:fitnep/app/app.dart';
import 'package:fitnep/core/services/firebase_providers.dart';
import 'package:fitnep/shared/widgets/fitnep_wordmark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/signed_out_auth.dart';

void main() {
  testWidgets(
    'startup failure stays retryable and opens the app after recovery',
    (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthProvider.overrideWithValue(SignedOutAuth()),
            firebaseInitializationProvider.overrideWith((ref) async {
              attempts++;
              if (attempts == 1) throw StateError('Test connection failure');
            }),
          ],
          child: const FitNepApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('We couldn’t connect.'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('welcome_carousel')), findsOneWidget);
      expect(attempts, 2);
    },
  );

  testWidgets('startup does not expose app routes before Firebase is ready', (
    tester,
  ) async {
    final ready = Completer<void>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(SignedOutAuth()),
          firebaseInitializationProvider.overrideWith((ref) => ready.future),
        ],
        child: const FitNepApp(),
      ),
    );
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(FitNepWordmark), findsOneWidget);
    final logo = tester.widget<Image>(find.byType(Image));
    expect((logo.image as AssetImage).assetName, FitNepWordmark.assetPath);
    expect(logo.width! / logo.height!, closeTo(641 / 615, 0.001));
    expect(find.byKey(const Key('welcome_carousel')), findsNothing);
    ready.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('welcome_carousel')), findsOneWidget);
  });

  testWidgets('branded startup fits a small screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final ready = Completer<void>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(SignedOutAuth()),
          firebaseInitializationProvider.overrideWith((ref) => ready.future),
        ],
        child: const FitNepApp(),
      ),
    );
    await tester.pump();
    expect(find.byType(FitNepWordmark), findsOneWidget);
    expect(tester.takeException(), isNull);
    ready.complete();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'welcome swipes, advances, and opens signup and login with larger text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthProvider.overrideWithValue(SignedOutAuth()),
            firebaseInitializationProvider.overrideWith((ref) async {}),
          ],
          child: const FitNepApp(),
        ),
      );
      await tester.pumpAndSettle();
      final carousel = find.byKey(const Key('welcome_carousel'));
      await tester.drag(carousel, const Offset(-280, 0));
      await tester.pumpAndSettle();
      expect(find.text('Your goals.\nYour kind of plan.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('welcome_next_button')));
      await tester.pumpAndSettle();
      expect(find.text('Get started'), findsOneWidget);
      await tester.tap(find.byKey(const Key('welcome_next_button')));
      await tester.pumpAndSettle();
      expect(find.text('Create your account'), findsOneWidget);
      await tester.ensureVisible(find.text('Back'));
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Get started'), findsOneWidget);
      await tester.tap(find.byKey(const Key('welcome_skip_button')));
      await tester.pumpAndSettle();
      expect(find.text('Welcome back'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
