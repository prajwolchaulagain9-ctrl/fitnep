import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitnep/app/app.dart';
import 'package:fitnep/app/routes/app_router.dart';
import 'package:fitnep/app/routes/app_routes.dart';
import 'package:fitnep/core/services/firebase_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _User extends Fake implements User {
  FirebaseAuthException? error;
  int refreshes = 0;
  @override
  String get uid => 'client';
  @override
  String get refreshToken => 'test-refresh-token';
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    expect(forceRefresh, isTrue);
    refreshes++;
    if (error != null) throw error!;
    return 'test-id-token';
  }
}

class _Auth extends Fake implements FirebaseAuth {
  _Auth(this.user);
  _User? user;
  final changes = StreamController<User?>.broadcast();
  @override
  User? get currentUser => user;
  @override
  Stream<User?> authStateChanges() async* {
    yield user;
    yield* changes.stream;
  }

  @override
  Future<void> signOut() async {
    user = null;
    changes.add(null);
  }
}

Future<ProviderContainer> _open(WidgetTester tester, _Auth auth) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firebaseInitializationProvider.overrideWith((ref) async {}),
        firebaseAuthProvider.overrideWithValue(auth),
      ],
      child: const FitNepApp(),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(FitNepApp)),
  );
  container.read(appRouterProvider).goNamed(AppRoutes.about);
  await tester.pumpAndSettle();
  return container;
}

Future<void> _close(WidgetTester tester, _Auth auth) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await auth.changes.close();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

void main() {
  testWidgets('revoked session is cleared on resume and returns to welcome', (
    tester,
  ) async {
    final user = _User();
    final auth = _Auth(user);
    await _open(tester, auth);
    user.error = FirebaseAuthException(code: 'user-token-expired');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(auth.currentUser == null, isTrue);
    expect(find.text('Learn about FitNEP'), findsOneWidget);
    await _close(tester, auth);
  });

  testWidgets('foreground refresh detects revocation without leaving the app', (
    tester,
  ) async {
    final user = _User();
    final auth = _Auth(user);
    await _open(tester, auth);
    user.error = FirebaseAuthException(code: 'user-token-expired');
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(auth.currentUser == null, isTrue);
    expect(find.text('Learn about FitNEP'), findsOneWidget);
    await _close(tester, auth);
  });

  testWidgets(
    'background pauses refresh and network failure preserves the session',
    (tester) async {
      final user = _User();
      final auth = _Auth(user);
      await _open(tester, auth);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final before = user.refreshes;
      await tester.pump(const Duration(seconds: 61));
      expect(user.refreshes, before);
      user.error = FirebaseAuthException(code: 'network-request-failed');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(auth.currentUser?.uid, 'client');
      expect(find.text('About FitNEP'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _close(tester, auth);
    },
  );
}
