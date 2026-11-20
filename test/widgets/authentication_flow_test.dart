import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitnep/app/app.dart';
import 'package:fitnep/app/routes/app_router.dart';
import 'package:fitnep/app/routes/app_routes.dart';
import 'package:fitnep/app/routes/route_access_gate.dart';
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
  MemorySessionPreferenceStore preferences, {
  FitNepRole? role = FitNepRole.client,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firebaseInitializationProvider.overrideWith((ref) async {}),
        firebaseAuthProvider.overrideWithValue(auth),
        sessionPreferenceStoreProvider.overrideWithValue(preferences),
        routeSessionProvider.overrideWith(
          (ref) async => auth.currentUser == null
              ? null
              : (uid: auth.currentUser!.uid, role: role),
        ),
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

  testWidgets('Firebase login reaches package selection and logs out', (
    tester,
  ) async {
    final auth = _Auth();
    final preferences = MemorySessionPreferenceStore();
    await _open(tester, auth, preferences);

    await tester.tap(find.byKey(const Key('welcome_login_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      ' client@example.com ',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'Password!12');
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();

    expect(auth.email, 'client@example.com');
    expect(auth.password, 'Password!12');
    expect(preferences.rememberSession, isTrue);
    expect(find.text('Choose a Package'), findsOneWidget);
    expect(find.text('Your FitNep updates'), findsNothing);

    await tester.tap(find.byTooltip('Sign out'));
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

    await tester.tap(find.byKey(const Key('welcome_login_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'client@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'wrong');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();
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

  testWidgets('a verified admin signs in to client management', (tester) async {
    final auth = _Auth();
    final container = await _open(
      tester,
      auth,
      MemorySessionPreferenceStore(),
      role: FitNepRole.admin,
    );
    final router = container.read(appRouterProvider);
    router.go(AppRoutes.loginPath);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'demo-admin@fitnep.test',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'Password!12');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Log in'));
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      AppRoutes.adminClients,
    );
    expect(find.text('Choose a Package'), findsNothing);
    expect(tester.takeException(), isNull);
    await _close(tester, auth);
  });

  testWidgets('remembered sessions open package selection on startup', (
    tester,
  ) async {
    final auth = _Auth(user: _User());
    await _open(
      tester,
      auth,
      MemorySessionPreferenceStore(rememberSession: true),
    );

    expect(find.text('Choose a Package'), findsOneWidget);
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
    expect(find.byKey(const Key('welcome_carousel')), findsOneWidget);
    expect(auth.signOuts, 1);
    await _close(tester, auth);
  });

  testWidgets('an unsupported account can sign out of the access screen', (
    tester,
  ) async {
    final auth = _Auth(user: _User());
    final container = await _open(
      tester,
      auth,
      MemorySessionPreferenceStore(rememberSession: true),
      role: null,
    );
    expect(find.text('Access denied'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();
    expect(auth.user, isNull);
    expect(find.text('Access denied'), findsNothing);
    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      AppRoutes.welcomePath,
    );
    expect(find.byKey(const Key('welcome_carousel')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _close(tester, auth);
  });
}
