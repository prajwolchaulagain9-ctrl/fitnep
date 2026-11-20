import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitnep/features/authentication/data/authentication_service.dart';
import 'package:fitnep/features/authentication/data/google_credential_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_session_preference_store.dart';

class _User extends Fake implements User {
  String? name;
  @override
  String get uid => 'client-1';

  @override
  Future<void> updateDisplayName(String? displayName) async {
    name = displayName;
  }
}

class _Credential extends Fake implements UserCredential {
  _Credential([this.user]);
  @override
  final User? user;
}

class _Google extends Fake implements GoogleCredentialProvider {
  AuthCredential? credential = GoogleAuthProvider.credential(
    idToken: 'test-token',
  );
  @override
  Future<AuthCredential?> authenticate() async => credential;
}

class _Auth extends Fake implements FirebaseAuth {
  User? user;
  FirebaseAuthException? signInError;
  String? email;
  String? password;
  int signIns = 0;
  int signOuts = 0;
  int signUps = 0;
  int googleSignIns = 0;
  AuthCredential? googleCredential;
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
    signIns++;
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

  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    signUps++;
    this.email = email;
    this.password = password;
    if (signInError != null) throw signInError!;
    user = _User();
    changes.add(user);
    return _Credential(user);
  }

  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    googleSignIns++;
    googleCredential = credential;
    user = _User();
    changes.add(user);
    return _Credential(user);
  }
}

void main() {
  late _Auth auth;
  late MemorySessionPreferenceStore preferences;
  late AuthenticationService service;

  setUp(() {
    auth = _Auth();
    preferences = MemorySessionPreferenceStore();
    service = AuthenticationService(
      auth: auth,
      sessionPreferences: preferences,
    );
  });

  tearDown(() async {
    await auth.changes.close();
  });

  test(
    'sign in uses Firebase and stores only the remember preference',
    () async {
      await service.signIn(
        email: ' client@example.com ',
        password: ' Password!12 ',
        rememberSession: true,
      );

      expect(auth.signIns, 1);
      expect(auth.email, 'client@example.com');
      expect(auth.password, ' Password!12 ');
      expect(preferences.rememberSession, isTrue);
      expect(preferences.writes, 1);
    },
  );

  test('invalid credentials use a safe public error', () async {
    auth.signInError = FirebaseAuthException(code: 'invalid-credential');

    await expectLater(
      service.signIn(
        email: 'client@example.com',
        password: 'wrong',
        rememberSession: false,
      ),
      throwsA(
        isA<AuthenticationFailure>()
            .having((error) => error.code, 'code', 'invalid-credential')
            .having(
              (error) => error.message,
              'message',
              'The email or password is incorrect.',
            ),
      ),
    );
  });

  test('restore signs out an explicitly unremembered session', () async {
    auth.user = _User();
    preferences.rememberSession = false;

    await service.restoreSession();

    expect(auth.signOuts, 1);
    expect(auth.currentUser, isNull);
  });

  test('restore preserves remembered and pre-policy sessions', () async {
    auth.user = _User();
    preferences.rememberSession = true;
    await service.restoreSession();
    expect(auth.signOuts, 0);

    preferences.rememberSession = null;
    await service.restoreSession();
    expect(auth.signOuts, 0);
  });

  test('logout clears Firebase state and the remember preference', () async {
    auth.user = _User();
    preferences.rememberSession = true;

    await service.signOut();

    expect(auth.signOuts, 1);
    expect(auth.currentUser, isNull);
    expect(preferences.rememberSession, isNull);
    expect(preferences.clears, 1);
  });

  test(
    'signup creates a Firebase account and saves its display name',
    () async {
      await service.signUp(
        name: ' Test Client ',
        email: ' client@example.com ',
        password: 'Password!12',
      );
      expect(auth.signUps, 1);
      expect(auth.email, 'client@example.com');
      expect(auth.password, 'Password!12');
      expect((auth.user as _User).name, 'Test Client');
      expect(preferences.rememberSession, isTrue);
    },
  );

  test('signup handles duplicate and weak-password errors', () async {
    for (final code in ['email-already-in-use', 'weak-password']) {
      auth.signInError = FirebaseAuthException(code: code);
      await expectLater(
        service.signUp(
          name: 'Client',
          email: 'client@example.com',
          password: 'bad',
        ),
        throwsA(
          isA<AuthenticationFailure>().having(
            (error) => error.code,
            'code',
            code,
          ),
        ),
      );
    }
    expect(auth.user, isNull);
  });

  test('Google sign-in exchanges the credential through Firebase', () async {
    final google = _Google();
    service = AuthenticationService(
      auth: auth,
      sessionPreferences: preferences,
      googleCredentials: google,
    );
    expect(await service.signInWithGoogle(rememberSession: false), isTrue);
    expect(auth.googleCredential?.providerId, 'google.com');
    expect(auth.googleSignIns, 1);
    expect(preferences.rememberSession, isFalse);
  });

  test(
    'canceling Google does not create a session or change persistence',
    () async {
      service = AuthenticationService(
        auth: auth,
        sessionPreferences: preferences,
        googleCredentials: _Google()..credential = null,
      );
      expect(await service.signInWithGoogle(rememberSession: true), isFalse);
      expect(auth.googleSignIns, 0);
      expect(preferences.writes, 0);
      expect(auth.user, isNull);
    },
  );
}
