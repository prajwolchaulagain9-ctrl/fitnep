import 'package:fitnep/features/authentication/data/registration_privacy.dart';

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitnep/app/app.dart';
import 'package:fitnep/app/routes/app_router.dart';
import 'package:fitnep/app/routes/app_routes.dart';
import 'package:fitnep/app/routes/route_access_gate.dart';
import 'package:fitnep/core/services/firebase_providers.dart';
import 'package:fitnep/features/authentication/presentation/controllers/authentication_controller.dart';
import 'package:fitnep/features/authentication/presentation/pages/change_staff_password_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_session_preference_store.dart';

class _User extends Fake implements User {
  _User({this.mustChangePassword = false});

  final bool mustChangePassword;

  @override
  bool get emailVerified => true;
  @override
  String get uid => 'client-1';

  @override
  Future<IdTokenResult> getIdTokenResult([bool forceRefresh = false]) async =>
      _Token(mustChangePassword);
}

class _Token extends Fake implements IdTokenResult {
  _Token(this.mustChangePassword);
  final bool mustChangePassword;

  @override
  Map<String, dynamic> get claims => {'mustChangePassword': mustChangePassword};
}

class _Credential extends Fake implements UserCredential {}

class _Auth extends Fake implements FirebaseAuth {
  _Auth({this.user, this.emitSignOut = true});

  User? user;
  final bool emitSignOut;
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
    if (emitSignOut) changes.add(null);
  }
}

Future<ProviderContainer> _open(
  WidgetTester tester,
  _Auth auth,
  MemorySessionPreferenceStore preferences, {
  Future<void> Function(String)? changePassword,
  FitNepRole? role = FitNepRole.client,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        registrationAcceptedProvider.overrideWith((ref, uid) async => true),
        if (changePassword != null)
          changeTemporaryPasswordProvider.overrideWithValue(changePassword),
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
  testWidgets(
    'temporary-password session must change password before opening a protected page',
    (tester) async {
      final auth = _Auth(user: _User(mustChangePassword: true));
      String? submitted;
      final container = await _open(
        tester,
        auth,
        MemorySessionPreferenceStore(rememberSession: true),
        changePassword: (password) async => submitted = password,
      );
      final router = container.read(appRouterProvider);
      router.go(AppRoutes.adminPackages);
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        AppRoutes.changeStaffPasswordPath,
      );
      expect(find.text('Change your temporary password'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField).first,
        'NewPassword!23',
      );
      await tester.enterText(find.byType(TextFormField).last, 'Mismatch!34');
      final button = find.widgetWithText(FilledButton, 'Change password');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Passwords must match.'), findsOneWidget);
      expect(submitted, isNull);
      await tester.enterText(find.byType(TextFormField).last, 'NewPassword!23');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(submitted, 'NewPassword!23');
      expect(auth.signOuts, 1);
      expect(
        router.routeInformationProvider.value.uri.path,
        AppRoutes.welcomePath,
      );
      await _close(tester, auth);
    },
  );

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

  testWidgets('logout returns to welcome even without a sign-out event', (
    tester,
  ) async {
    final auth = _Auth(emitSignOut: false);
    final preferences = MemorySessionPreferenceStore();
    final container = await _open(tester, auth, preferences);
    final router = container.read(appRouterProvider);
    router.goNamed(AppRoutes.welcome);
    await tester.pumpAndSettle();

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
    expect(
      router.routeInformationProvider.value.uri.path,
      AppRoutes.welcomePath,
    );
    expect(find.byKey(const Key('welcome_carousel')), findsOneWidget);
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

  testWidgets('logout replaces a signed-in page opened above a public route', (
    tester,
  ) async {
    final auth = _Auth(user: _User());
    final container = await _open(
      tester,
      auth,
      MemorySessionPreferenceStore(rememberSession: true),
    );
    final router = container.read(appRouterProvider);
    router.goNamed(AppRoutes.about);
    await tester.pumpAndSettle();
    unawaited(router.pushNamed(AppRoutes.clientPackagesName));
    await tester.pumpAndSettle();
    expect(router.canPop(), isTrue);

    final logout = find.byTooltip('Sign out');
    await tester.ensureVisible(logout);
    await tester.tap(logout);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('welcome_carousel')), findsOneWidget);
    expect(router.canPop(), isFalse);
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

    expect(find.text('Choose a Package'), findsNothing);
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
