import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitnep/app/app.dart';
import 'package:fitnep/app/routes/app_router.dart';
import 'package:fitnep/app/routes/app_routes.dart';
import 'package:fitnep/core/services/firebase_providers.dart';
import 'package:fitnep/features/authentication/presentation/controllers/authentication_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_session_preference_store.dart';

class _User extends Fake implements User {
  @override
  bool get emailVerified => true;
  @override
  String get uid => 'client-1';
}

class _Credential extends Fake implements UserCredential {}

class _Auth extends Fake implements FirebaseAuth {
  _Auth({this.user});

  User? user;
  FirebaseAuthException? signInError;
  String? email;
  String? password;
  int signOuts = 0;
  final changes = StreamController<User?>.broadcast();

  @override
  User? get currentUser => user;

  @override
  Stream<User?> authStateChanges() async* {
    yield user;
    yield* changes.stream;
  }

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    this.email = email;
    this.password = password;
    if (signInError != null) throw signInError!;
    user = _User();
    changes.add(user);
    return _Credential();
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    user = null;
    changes.add(null);
  }
}

Future<ProviderContainer> _open(
  WidgetTester tester,
  _Auth auth,
  MemorySessionPreferenceStore preferences,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firebaseInitializationProvider.overrideWith((ref) async {}),
        firebaseAuthProvider.overrideWithValue(auth),
        sessionPreferenceStoreProvider.overrideWithValue(preferences),
      ],
      child: const FitNepApp(),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(FitNepApp)));
}

Future<void> _close(WidgetTester tester, _Auth auth) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await auth.changes.close();
}

void main() {
  testWidgets('signed-out users are redirected away from protected routes', (
    tester,
  ) async {
    final auth = _Auth();
    final container = await _open(tester, auth, MemorySessionPreferenceStore());

    container.read(appRouterProvider).go(AppRoutes.clientHome);
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Client Home'), findsNothing);
    await _close(tester, auth);
  });

  testWidgets('real Firebase login reaches development screen and logs out', (
    tester,
  ) async {
    final auth = _Auth();
    final preferences = MemorySessionPreferenceStore();
    await _open(tester, auth, preferences);

    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      ' client@example.com ',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'Password!12');
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();

    expect(auth.email, 'client@example.com');
    expect(auth.password, 'Password!12');
    expect(preferences.rememberSession, isTrue);
    expect(find.text('App Under Development'), findsOneWidget);
    expect(find.text('Coming Soon'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Logout'));
    await tester.pumpAndSettle();

    expect(auth.signOuts, 1);
    expect(preferences.rememberSession, isNull);
    expect(find.text('Welcome back'), findsOneWidget);
    await _close(tester, auth);
  });

  testWidgets('login failures are shown without exposing Firebase details', (
    tester,
  ) async {
    final auth = _Auth()
      ..signInError = FirebaseAuthException(code: 'invalid-credential');
    await _open(tester, auth, MemorySessionPreferenceStore());

    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'client@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'wrong');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();

    expect(find.text('The email or password is incorrect.'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(1))
          .controller
          ?.text,
      isEmpty,
    );
    await _close(tester, auth);
  });

  testWidgets('remembered sessions open the development screen on startup', (
    tester,
  ) async {
    final auth = _Auth(user: _User());
    await _open(
      tester,
      auth,
      MemorySessionPreferenceStore(rememberSession: true),
    );

    expect(find.text('App Under Development'), findsOneWidget);
    expect(auth.signOuts, 0);
    await _close(tester, auth);
  });

  testWidgets('unremembered sessions sign out before protected UI appears', (
    tester,
  ) async {
    final auth = _Auth(user: _User());
    await _open(
      tester,
      auth,
      MemorySessionPreferenceStore(rememberSession: false),
    );

    expect(find.text('App Under Development'), findsNothing);
    expect(find.text('Learn about FitNEP'), findsOneWidget);
    expect(auth.signOuts, 1);
    await _close(tester, auth);
  });
}
