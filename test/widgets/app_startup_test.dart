import 'dart:async';

import 'package:fitnep/app/app.dart';
import 'package:fitnep/core/services/firebase_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'startup failure stays retryable and opens the app after recovery',
    (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
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
      expect(find.text('Learn about FitNEP'), findsOneWidget);
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
          firebaseInitializationProvider.overrideWith((ref) => ready.future),
        ],
        child: const FitNepApp(),
      ),
    );
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Learn about FitNEP'), findsNothing);
    ready.complete();
    await tester.pumpAndSettle();
    expect(find.text('Learn about FitNEP'), findsOneWidget);
  });

  testWidgets('welcome navigation works on a small screen with larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseInitializationProvider.overrideWith((ref) async {}),
        ],
        child: const FitNepApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Learn about FitNEP'));
    await tester.tap(find.text('Learn about FitNEP'));
    await tester.pumpAndSettle();
    expect(find.text('About FitNEP'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Back to welcome'));
    await tester.tap(find.text('Back to welcome'));
    await tester.pumpAndSettle();
    expect(find.text('Learn about FitNEP'), findsOneWidget);
  });
}
