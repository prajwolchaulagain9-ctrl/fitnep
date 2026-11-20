import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitnep/app/app.dart';
import 'package:fitnep/app/routes/app_router.dart';
import 'package:fitnep/app/routes/app_routes.dart';
import 'package:fitnep/core/services/firebase_providers.dart';
import 'package:fitnep/features/authentication/data/authentication_service.dart';
import 'package:fitnep/features/authentication/data/email_verification_service.dart';
import 'package:fitnep/features/authentication/data/google_credential_provider.dart';
import 'package:fitnep/features/authentication/presentation/controllers/authentication_controller.dart';
import 'package:fitnep/shared/widgets/fitnep_wordmark.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_session_preference_store.dart';

class _ProviderInfo extends Fake implements UserInfo {
  @override
  String get providerId => 'password';
}

class _User extends Fake implements User {
  @override
  String get uid => 'signup-client';
  @override
  String get email => 'client@example.com';
  @override
  bool emailVerified = false;
  @override
  List<UserInfo> get providerData => [_ProviderInfo()];
  @override
  Future<void> updateDisplayName(String? displayName) async {}
}

class _Credential extends Fake implements UserCredential {
  _Credential(this.user);
  @override
  final User? user;
}

class _Auth extends Fake implements FirebaseAuth {
  _User? user;
  int signUps = 0;
  int googleSignIns = 0;
  final changes = StreamController<User?>.broadcast();
  @override
  User? get currentUser => user;
  @override
  Stream<User?> authStateChanges() async* {
    yield user;
    yield* changes.stream;
  }

  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    signUps++;
    user = _User();
    changes.add(user);
    return _Credential(user);
  }

  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    googleSignIns++;
    user = _User()..emailVerified = true;
    changes.add(user);
    return _Credential(user);
  }

  @override
  Future<void> signOut() async {
    user = null;
    changes.add(null);
  }
}

class _Google extends Fake implements GoogleCredentialProvider {
  bool cancel = false;
  @override
  Future<AuthCredential?> authenticate() async =>
      cancel ? null : GoogleAuthProvider.credential(idToken: 'test-token');
}

class _Verification extends Fake implements EmailVerificationService {
  _Verification(this.auth);
  @override
  final _Auth auth;
  int sends = 0;
  @override
  Future<EmailCodeDelivery> sendCode({bool resend = false}) async {
    sends++;
    return const EmailCodeDelivery(resendAfterSeconds: 60);
  }

  @override
  Future<void> verifyCode(String code) async {
    if (code != '123456') {
      throw const AuthenticationFailure(
        'That code is incorrect. Please try again.',
      );
    }
    auth.user!.emailVerified = true;
  }
}

final _capture = GlobalKey();
bool _fontsLoaded = false;

Future<void> _loadCaptureFonts() async {
  if (_fontsLoaded) return;
  final configFile = File('.dart_tool/package_config.json');
  final config = jsonDecode(await configFile.readAsString()) as Map;
  final package = (config['packages'] as List).cast<Map>().firstWhere(
    (package) => package['name'] == 'flutter',
  );
  final flutterUri = configFile.absolute.uri.resolve(
    package['rootUri'] as String,
  );
  final sdk = Directory.fromUri(flutterUri).parent.parent;
  final fonts = '${sdk.path}/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final weight in ['regular', 'medium', 'bold']) {
    roboto.addFont(
      File('$fonts/roboto-$weight.ttf')
          .readAsBytes()
          .then(ByteData.sublistView),
    );
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      File('$fonts/materialicons-regular.otf')
          .readAsBytes()
          .then(ByteData.sublistView),
    );
  await icons.load();
  _fontsLoaded = true;
}

Future<ProviderContainer> _open(
  WidgetTester tester,
  _Auth auth, {
  bool? otp,
  _Google? google,
  _Verification? verification,
}) async {
  if (const bool.fromEnvironment('FITNEP_CAPTURE_AUTH_UI')) {
    await tester.runAsync(_loadCaptureFonts);
  }
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firebaseInitializationProvider.overrideWith((ref) async {}),
        firebaseAuthProvider.overrideWithValue(auth),
        sessionPreferenceStoreProvider.overrideWithValue(
          MemorySessionPreferenceStore(),
        ),
        if (otp != null) signupEmailOtpEnabledProvider.overrideWithValue(otp),
        googleCredentialProvider.overrideWithValue(google ?? _Google()),
        emailVerificationServiceProvider.overrideWithValue(
          verification ?? _Verification(auth),
        ),
      ],
      child: RepaintBoundary(key: _capture, child: const FitNepApp()),
    ),
  );
  await tester.pumpAndSettle();
  if (const bool.fromEnvironment('FITNEP_CAPTURE_AUTH_UI')) {
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/icons/google_g.png'),
        tester.element(find.byType(FitNepApp)),
      ),
    );
    await tester.pumpAndSettle();
  }
  return ProviderScope.containerOf(tester.element(find.byType(FitNepApp)));
}

Future<void> _close(WidgetTester tester, _Auth auth) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await auth.changes.close();
}

Future<void> _fill(
  WidgetTester tester, {
  String confirmation = 'Password!12',
}) async {
  await tester.enterText(find.byType(TextFormField).at(0), 'Test Client');
  await tester.enterText(
    find.byType(TextFormField).at(1),
    'client@example.com',
  );
  await tester.enterText(find.byType(TextFormField).at(2), 'Password!12');
  await tester.enterText(find.byType(TextFormField).at(3), confirmation);
  await tester.ensureVisible(
    find.widgetWithText(FilledButton, 'Create account'),
  );
  await tester.pumpAndSettle();
}

Future<void> _snapshot(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('FITNEP_CAPTURE_AUTH_UI')) return;
  await tester.runAsync(() async {
    final boundary =
        _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final screenshot = await boundary.toImage();
    final bytes = await screenshot.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('build/qa/authentication');
    await directory.create(recursive: true);
    await File('${directory.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    screenshot.dispose();
  });
}

void main() {
  testWidgets('login links to branded signup with consistent mobile fields', (
    tester,
  ) async {
    final auth = _Auth();
    final container = await _open(tester, auth);
    container.read(appRouterProvider).go(AppRoutes.loginPath);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(TextButton, 'Sign up'));
    await tester.tap(find.widgetWithText(TextButton, 'Sign up'));
    await tester.pumpAndSettle();
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.byType(FitNepWordmark), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(4));
    await _snapshot(tester, 'signup-top');
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Create account'),
    );
    await tester.pumpAndSettle();
    await _snapshot(tester, 'signup-bottom');
    expect(tester.takeException(), isNull);
    await _close(tester, auth);
  });

  testWidgets('mismatched signup passwords prevent account creation', (
    tester,
  ) async {
    final auth = _Auth();
    final container = await _open(tester, auth);
    container.read(appRouterProvider).go(AppRoutes.signupPath);
    await tester.pumpAndSettle();
    await _fill(tester, confirmation: 'Different!12');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(auth.signUps, 0);
    await _close(tester, auth);
  });

  testWidgets('signup enters development screen when OTP is disabled', (
    tester,
  ) async {
    final auth = _Auth();
    final container = await _open(tester, auth, otp: false);
    container.read(appRouterProvider).go(AppRoutes.signupPath);
    await tester.pumpAndSettle();
    await _fill(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(auth.signUps, 1);
    expect(find.text('App Under Development'), findsOneWidget);
    await _close(tester, auth);
  });

  testWidgets('OTP phase blocks protected routes until the code verifies', (
    tester,
  ) async {
    final auth = _Auth();
    final verification = _Verification(auth);
    final container = await _open(tester, auth, verification: verification);
    container.read(appRouterProvider).go(AppRoutes.signupPath);
    await tester.pumpAndSettle();
    await _fill(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Verify your email'), findsOneWidget);
    expect(verification.sends, 1);
    expect(find.text('Resend code in 60s'), findsOneWidget);
    await _snapshot(tester, 'verify-email');
    container.read(appRouterProvider).go(AppRoutes.clientHome);
    await tester.pumpAndSettle();
    expect(find.text('Verify your email'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '000000');
    await tester.tap(find.widgetWithText(FilledButton, 'Verify email'));
    await tester.pumpAndSettle();
    expect(
      find.text('That code is incorrect. Please try again.'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextFormField), '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Verify email'));
    await tester.pumpAndSettle();
    expect(find.text('App Under Development'), findsOneWidget);
    await _close(tester, auth);
  });

  testWidgets(
    'Google cancellation keeps signup usable and success enters the app',
    (tester) async {
      final auth = _Auth();
      final google = _Google()..cancel = true;
      final container = await _open(tester, auth, otp: true, google: google);
      container.read(appRouterProvider).go(AppRoutes.signupPath);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      expect(find.text('Create your account'), findsOneWidget);
      expect(auth.googleSignIns, 0);
      google.cancel = false;
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      expect(auth.googleSignIns, 1);
      expect(find.text('App Under Development'), findsOneWidget);
      expect(find.text('Verify your email'), findsNothing);
      await _close(tester, auth);
    },
  );
}
