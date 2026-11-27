import '../support/empty_package_catalog.dart';
import '../support/offline_hosted_session.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fitnep/features/authentication/data/registration_privacy.dart';
import 'package:fitnep/app/app.dart';
import 'package:fitnep/app/routes/app_router.dart';
import 'package:fitnep/app/routes/app_routes.dart';
import 'package:fitnep/app/routes/route_access_gate.dart';
import 'package:fitnep/features/notifications/presentation/controllers/notification_controller.dart';
import 'package:fitnep/core/services/firebase_providers.dart';
import 'package:fitnep/features/authentication/data/authentication_service.dart';
import 'package:fitnep/features/authentication/data/email_verification_service.dart';
import 'package:fitnep/features/authentication/data/google_credential_provider.dart';
import 'package:fitnep/features/authentication/presentation/controllers/authentication_controller.dart';
import 'package:fitnep/features/authorization/data/authorization_repository.dart';
import 'package:fitnep/features/health_assessment/data/repositories/intake_workspace_repository.dart';
import 'package:fitnep/features/health_assessment/domain/entities/client_intake_form.dart';
import 'package:fitnep/shared/widgets/fitnep_wordmark.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_session_preference_store.dart';
import '../support/empty_notifications.dart';

class _IntakeWorkspace extends Fake implements IntakeWorkspaceRepository {
  @override
  Future<IntakeFormWorkspace> load(String uid) async =>
      const IntakeFormWorkspace(
        answers: {},
        version: 0,
        draftRevision: 0,
        profileReady: true,
      );
}

class _SignupProfile extends Fake implements AuthorizationRepository {
  Map<String, dynamic>? saved;

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? data,
    Map<String, dynamic>? query,
  }) async {
    expect(path, 'profile/me');
    if (method == 'PATCH') saved = data;
    return {
      'account': {
        'id': 'signup-client',
        'full_name': 'Test Client',
        'email': 'client@example.com',
        'role': 'client',
        'account_status': 'active',
        'created_at': '2026-11-27T00:00:00Z',
        'updated_at': '2026-11-27T00:00:00Z',
        ...?saved,
      },
    };
  }
}

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
  bool emitSignOut = true;
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
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    user = _User()..emailVerified = true;
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
    if (emitSignOut) changes.add(null);
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
  bool failToSendCode = false;

  @override
  Future<EmailCodeDelivery> sendVerificationLink() async =>
      const EmailCodeDelivery(
        resendAfterSeconds: 60,
        usesVerificationLink: true,
      );

  @override
  Future<bool> checkVerificationLink() async {
    auth.user!.emailVerified = true;
    return true;
  }

  @override
  Future<EmailCodeDelivery> sendCode({bool resend = false}) async {
    sends++;
    if (failToSendCode) {
      throw const EmailVerificationFailure(
        'Email verification is unavailable.',
      );
    }
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
  final inter = FontLoader('Inter')
    ..addFont(
      File('assets/fonts/Inter-Variable.ttf')
          .readAsBytes()
          .then(ByteData.sublistView),
    );
  await inter.load();
  _fontsLoaded = true;
}

Future<ProviderContainer> _open(
  WidgetTester tester,
  _Auth auth, {
  _Google? google,
  _Verification? verification,
  RegistrationPrivacyRequest? privacy,
  Future<bool> Function()? staffPasswordCheck,
}) async {
  if (const bool.fromEnvironment('FITNEP_CAPTURE_AUTH_UI')) {
    await tester.runAsync(_loadCaptureFonts);
  }
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        emptyPackageCatalogOverride,
        emptyMembershipOverride,
        authorizationRepositoryProvider.overrideWithValue(_SignupProfile()),
        intakeWorkspaceRepositoryProvider.overrideWithValue(_IntakeWorkspace()),
        offlineHostedSessionOverride,
        staffPasswordChangeRequiredProvider.overrideWith((ref) async {
          if (staffPasswordCheck == null) return false;
          final user = await ref.watch(authenticationStateProvider.future);
          ref.watch(tokenStorageProvider);
          return user == null ? false : staffPasswordCheck();
        }),
        firebaseInitializationProvider.overrideWith((ref) async {}),
        firebaseAuthProvider.overrideWithValue(auth),
        routeSessionProvider.overrideWith((ref) async {
          final user = await ref.watch(authenticationStateProvider.future);
          return user == null
              ? null
              : (uid: user.uid, role: FitNepRole.client, auditRead: false);
        }),
        notificationControllerProvider.overrideWith(EmptyNotifications.new),
        sessionPreferenceStoreProvider.overrideWithValue(
          MemorySessionPreferenceStore(),
        ),
        registrationPrivacyProvider.overrideWithValue(
          privacy ?? (data) async => true,
        ),
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
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/icons/google_g.png'),
        tester.element(find.byType(FitNepApp)),
      );
      await precacheImage(
        const AssetImage(FitNepWordmark.assetPath),
        tester.element(find.byType(FitNepApp)),
      );
    });
    await tester.pumpAndSettle();
  }
  return ProviderScope.containerOf(tester.element(find.byType(FitNepApp)));
}

Future<void> _signInExisting(
  WidgetTester tester,
  ProviderContainer container,
) async {
  container.read(appRouterProvider).goNamed(AppRoutes.login);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byType(TextFormField).at(0),
    'client@example.com',
  );
  await tester.enterText(find.byType(TextFormField).at(1), 'Password!12');
  final login = find.widgetWithText(FilledButton, 'Log in');
  await tester.ensureVisible(login);
  await tester.tap(login);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
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
  await tester.pump();
}

Future<void> _createAccount(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('signup_agreement')));
  await tester.tap(find.byKey(const Key('signup_agreement')));
  final create = find.widgetWithText(FilledButton, 'Create account');
  await tester.ensureVisible(create);
  await tester.tap(create);
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
  testWidgets(
    'Google password recovery remains reachable without reopening startup',
    (tester) async {
      final auth = _Auth();
      final container = await _open(tester, auth);
      await _signInExisting(tester, container);
      final router = container.read(appRouterProvider);
      router.go('${AppRoutes.changeStaffPasswordPath}?recover=google');
      await tester.pumpAndSettle();
      expect(find.text('Change your temporary password'), findsOneWidget);
      expect(find.text('Checking your account…'), findsNothing);
      router.go(AppRoutes.changeStaffPasswordPath);
      await tester.pumpAndSettle();
      expect(find.text('Choose a package'), findsOneWidget);
      await _close(tester, auth);
    },
  );

  testWidgets(
    'Google sign-in checks the account once and does not reopen startup',
    (tester) async {
      final auth = _Auth();
      var checks = 0;
      final container = await _open(
        tester,
        auth,
        staffPasswordCheck: () async {
          checks++;
          return false;
        },
      );
      container.read(appRouterProvider).go(AppRoutes.loginPath);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expect(checks, 1);
      expect(find.text('Choose a package'), findsOneWidget);
      expect(find.text('Checking your account…'), findsNothing);
      expect(find.text('We couldn’t connect.'), findsNothing);
      await _close(tester, auth);
    },
  );

  testWidgets('an account service error after login still allows sign-out', (
    tester,
  ) async {
    final auth = _Auth();
    final container = await _open(
      tester,
      auth,
      staffPasswordCheck: () async {
        throw StateError('Session endpoint unavailable');
      },
    );
    await _signInExisting(tester, container);
    await tester.pumpAndSettle();
    expect(find.text('We couldn’t connect.'), findsOneWidget);
    expect(find.text('Choose a package'), findsNothing);
    await tester.tap(find.text('Use another account'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('welcome_carousel')), findsOneWidget);
    expect(auth.currentUser, isNull);
    await _close(tester, auth);
  });

  testWidgets(
    'an existing client can read the policy and retry after the privacy service fails',
    (tester) async {
      final auth = _Auth();
      var available = false;
      final container = await _open(
        tester,
        auth,
        privacy: (_) async {
          if (!available) {
            throw FirebaseFunctionsException(
              code: 'unimplemented',
              message: 'Endpoint unavailable',
            );
          }
          return true;
        },
      );
      await _signInExisting(tester, container);
      await tester.pumpAndSettle();
      expect(
        find.text('The privacy service is temporarily unavailable.'),
        findsOneWidget,
      );
      expect(find.text('Choose a package'), findsNothing);

      await tester.tap(find.text('Read Privacy Policy'));
      await tester.pumpAndSettle();
      expect(find.text('How FitNEP handles your data'), findsOneWidget);
      container.read(appRouterProvider).pop();
      await tester.pumpAndSettle();

      available = true;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a package'), findsOneWidget);
      await _close(tester, auth);
    },
  );

  testWidgets(
    'a stalled privacy check times out and another account can be used while retrying',
    (tester) async {
      final auth = _Auth()..emitSignOut = false;
      final pending = Completer<bool>();
      final container = await _open(
        tester,
        auth,
        privacy: (_) => pending.future,
      );
      await _signInExisting(tester, container);
      expect(
        find.text('Checking your privacy policy acceptance…'),
        findsOneWidget,
      );
      expect(find.text('Use another account'), findsOneWidget);
      await tester.pump(const Duration(seconds: 26));
      await tester.pumpAndSettle();
      expect(
        find.text('The privacy check took too long. Please try again.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(
        find.text('Checking your privacy policy acceptance…'),
        findsOneWidget,
      );
      await tester.tap(find.text('Use another account'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('welcome_carousel')), findsOneWidget);
      expect(auth.currentUser, isNull);

      pending.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('Choose a package'), findsNothing);
      await _close(tester, auth);
    },
  );

  testWidgets(
    'an existing client can retry saving consent without reviewing it again',
    (tester) async {
      final auth = _Auth();
      var attempts = 0;
      var saved = false;
      final container = await _open(
        tester,
        auth,
        privacy: (data) async {
          if (data['action'] == 'status') return saved;
          expect(data.containsKey('age'), isFalse);
          expect(data['terms_accepted'], isTrue);
          expect(data['privacy_policy_accepted'], isTrue);
          attempts++;
          if (attempts == 1) throw StateError('Consent save unavailable');
          saved = true;
          return saved;
        },
      );
      await _signInExisting(tester, container);
      await tester.pumpAndSettle();
      expect(find.text('Complete registration'), findsOneWidget);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('Agree and continue'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not save your agreement. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Choose a package'), findsNothing);
      await tester.tap(find.text('Agree and continue'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a package'), findsOneWidget);
      expect(attempts, 2);
      await _close(tester, auth);
    },
  );

  testWidgets('privacy policy is readable before signup and OTP verification', (
    tester,
  ) async {
    final auth = _Auth();
    final container = await _open(tester, auth);
    final router = container.read(appRouterProvider);
    router.goNamed(AppRoutes.privacyPolicy);
    await tester.pumpAndSettle();
    expect(find.text('How FitNEP handles your data'), findsOneWidget);

    await auth.createUserWithEmailAndPassword(
      email: 'client@example.com',
      password: 'Password!12',
    );
    await tester.pumpAndSettle();
    expect(find.text('How FitNEP handles your data'), findsOneWidget);

    router.go(AppRoutes.clientHome);
    await tester.pumpAndSettle();
    expect(find.text('Verify your email'), findsOneWidget);
    router.goNamed(AppRoutes.privacyPolicy);
    await tester.pumpAndSettle();
    expect(find.text('How FitNEP handles your data'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _close(tester, auth);
  });

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
    final continueButton = find.widgetWithText(FilledButton, 'Create account');
    await tester.ensureVisible(continueButton);
    await tester.tap(continueButton);
    await tester.pumpAndSettle();
    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(auth.signUps, 0);
    await _close(tester, auth);
  });

  testWidgets('signup can use a verification link after code delivery fails', (
    tester,
  ) async {
    final auth = _Auth();
    final verification = _Verification(auth)..failToSendCode = true;
    final container = await _open(tester, auth, verification: verification);
    container.read(appRouterProvider).go(AppRoutes.signupPath);
    await tester.pumpAndSettle();
    await _fill(tester);
    await _createAccount(tester);
    final fallback = find.text('Send a verification link instead');
    await tester.ensureVisible(fallback);
    await tester.tap(fallback);
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
    final verify = find.text('I verified my email');
    await tester.ensureVisible(verify);
    await tester.tap(verify);
    await tester.pumpAndSettle();
    expect(find.text('My profile'), findsOneWidget);
    await _close(tester, auth);
  });

  testWidgets(
    'terms consent is saved after verification while age is deferred',
    (tester) async {
      final auth = _Auth();
      Map<String, Object>? savedConsent;
      final container = await _open(
        tester,
        auth,
        privacy: (data) async {
          expect(auth.currentUser?.emailVerified, isTrue);
          if (data['action'] == 'accept') savedConsent = data;
          return savedConsent != null;
        },
      );
      container.read(appRouterProvider).go(AppRoutes.signupPath);
      await tester.pumpAndSettle();
      await _fill(tester);
      await _createAccount(tester);
      expect(find.text('Verify your email'), findsOneWidget);
      expect(savedConsent, isNull);
      await tester.enterText(find.byType(TextFormField), '123456');
      await tester.tap(find.widgetWithText(FilledButton, 'Verify email'));
      await tester.pumpAndSettle();
      expect(savedConsent, containsPair('uid', 'signup-client'));
      expect(savedConsent!.containsKey('age'), isFalse);
      expect(savedConsent, containsPair('terms_accepted', true));
      expect(savedConsent, containsPair('guardian_consent_confirmed', false));
      expect(find.text('My profile'), findsOneWidget);
      final birthDate = find.widgetWithText(TextField, 'Date of birth');
      expect(find.byKey(const ValueKey('height_cm')), findsNothing);
      final year = DateTime.now().toUtc().year - 17;
      await tester.ensureVisible(birthDate);
      await tester.enterText(birthDate, '$year-01-01');
      await tester.pumpAndSettle();
      expect(find.text('Parent or guardian consent'), findsOneWidget);
      await tester.tap(find.text('Confirm permission'));
      await tester.pumpAndSettle();
      final next = find.text('Continue to health intake');
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
      final repository =
          container.read(authorizationRepositoryProvider) as _SignupProfile;
      expect(repository.saved?['guardian_consent_confirmed'], true);
      expect(repository.saved?['date_of_birth'], '$year-01-01');
      expect(find.text('Step 1 of 3'), findsOneWidget);
      expect(find.text('Date of birth'), findsNothing);
      final finishLater = find.text('Finish later');
      await tester.ensureVisible(finishLater);
      await tester.tap(finishLater);
      await tester.pumpAndSettle();
      expect(find.text('Welcome back'), findsOneWidget);
      await _close(tester, auth);
    },
  );

  testWidgets('OTP phase blocks protected routes until the code verifies', (
    tester,
  ) async {
    final auth = _Auth();
    final verification = _Verification(auth);
    final container = await _open(tester, auth, verification: verification);
    container.read(appRouterProvider).go(AppRoutes.signupPath);
    await tester.pumpAndSettle();
    await _fill(tester);
    await _createAccount(tester);
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
    expect(find.text('My profile'), findsOneWidget);
    await _close(tester, auth);
  });

  testWidgets(
    'Google cancellation keeps signup usable and success enters the app',
    (tester) async {
      final auth = _Auth();
      final google = _Google()..cancel = true;
      final container = await _open(tester, auth, google: google);
      container.read(appRouterProvider).go(AppRoutes.signupPath);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('signup_agreement')));
      await tester.ensureVisible(find.text('Continue with Google'));
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      expect(find.text('Create your account'), findsOneWidget);
      expect(auth.googleSignIns, 0);
      google.cancel = false;
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      expect(auth.googleSignIns, 1);
      expect(find.text('My profile'), findsOneWidget);
      expect(find.text('Verify your email'), findsNothing);
      await _close(tester, auth);
    },
  );
}
