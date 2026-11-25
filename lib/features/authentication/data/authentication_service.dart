import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'google_credential_provider.dart';
import 'session_preference_store.dart';

class AuthenticationFailure implements Exception {
  const AuthenticationFailure(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class AuthenticationService {
  const AuthenticationService({
    required this.auth,
    required this.sessionPreferences,
    this.googleCredentials,
    this.beforeSignOut,
    this.afterGoogleSignIn,
  });

  final FirebaseAuth auth;
  final SessionPreferenceStore sessionPreferences;
  final GoogleCredentialProvider? googleCredentials;
  final Future<void> Function()? beforeSignOut;
  final Future<void> Function()? afterGoogleSignIn;

  Stream<User?> authStateChanges() => auth.authStateChanges();

  Future<void> restoreSession() async {
    if (auth.currentUser == null) return;

    final rememberSession = await sessionPreferences.readRememberSession();
    // A missing preference belongs to a session created before this policy was
    // introduced. Preserve it; every new login writes an explicit preference.
    if (rememberSession == false) {
      await beforeSignOut?.call();
      await auth.signOut();
    }
  }

  Future<void> signIn({
    required String email,
    required String password,
    required bool rememberSession,
  }) async {
    try {
      // Store only the persistence choice. Firebase owns all credentials and
      // refresh tokens through its native Android/iOS SDK storage.
      await sessionPreferences.writeRememberSession(rememberSession);
    } catch (_) {
      throw const AuthenticationFailure(
        'We couldn\u2019t save your session preference. Please try again.',
        code: 'session-preference-unavailable',
      );
    }

    try {
      await auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (error) {
      throw failureFor(error);
    } catch (_) {
      throw const AuthenticationFailure(
        'We couldn\u2019t sign you in. Please try again.',
      );
    }
  }

  Future<void> signOut() async {
    try {
      await beforeSignOut?.call();
      await auth.signOut();
    } on FirebaseAuthException catch (error) {
      throw AuthenticationFailure(
        'We couldn\u2019t sign you out. Please try again.',
        code: error.code,
      );
    } catch (_) {
      throw const AuthenticationFailure(
        'We couldn\u2019t sign you out. Please try again.',
      );
    }

    try {
      await sessionPreferences.clearRememberSession();
    } catch (_) {
      // Firebase has already cleared the authenticated session. A stale
      // non-secret preference cannot authenticate a user and is overwritten
      // by the next successful login.
    }
  }

  Future<String?> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      await sessionPreferences.writeRememberSession(true);
    } catch (_) {
      throw const AuthenticationFailure(
        'We couldn\u2019t save your session preference. Please try again.',
      );
    }
    try {
      final result = await auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      // Creating an account signs it in immediately. Profile failures must not
      // tell the user to create the same account again.
      try {
        await result.user?.updateDisplayName(name.trim());
      } catch (_) {
        // Name can be completed in the profile phase; authentication succeeded.
      }
      return result.user?.uid;
    } on FirebaseAuthException catch (error) {
      throw failureFor(error);
    } catch (_) {
      throw const AuthenticationFailure(
        'We couldn\u2019t create your account. Please try again.',
      );
    }
  }

  Future<bool> signInWithGoogle({required bool rememberSession}) async {
    try {
      AuthCredential? credential;
      if (kIsWeb) {
        await sessionPreferences.writeRememberSession(rememberSession);
        credential = (await auth.signInWithPopup(GoogleAuthProvider()))
            .credential;
      } else {
        credential =
            await (googleCredentials ?? NativeGoogleCredentialProvider())
                .authenticate();
        if (credential == null) return false;
        await sessionPreferences.writeRememberSession(rememberSession);
        await auth.signInWithCredential(credential);
      }
      if (afterGoogleSignIn != null) {
        final user = auth.currentUser;
        final hasPassword =
            user?.providerData.any(
              (provider) => provider.providerId == 'password',
            ) ==
            true;
        final temporary = hasPassword
            ? ((await user!.getIdTokenResult())
                      .claims?['googleTemporaryPasswordUntil']
                  is num)
            : false;
        if (user != null && (!hasPassword || temporary)) {
          try {
            await afterGoogleSignIn!();
          } finally {
            // Installing a Firebase password revokes the previous credentials.
            // Re-exchange the Google credential so its current session survives.
            if (credential != null) await auth.signInWithCredential(credential);
          }
        }
      }
      return true;
    } on AuthenticationFailure {
      rethrow;
    } on FirebaseAuthException catch (error) {
      if (error.code == 'popup-closed-by-user' ||
          error.code == 'cancelled-popup-request') {
        return false;
      }
      throw error.code == 'operation-not-allowed'
          ? const AuthenticationFailure(
              'Google sign-in is unavailable right now. Please use email instead.',
            )
          : failureFor(error);
    } catch (_) {
      throw const AuthenticationFailure(
        'We couldn\u2019t sign you in with Google. Please try again.',
      );
    }
  }

  static AuthenticationFailure failureFor(FirebaseAuthException error) {
    return switch (error.code) {
      'email-already-in-use' => const AuthenticationFailure(
        'We couldn\u2019t create this account. Try logging in or resetting your password.',
        code: 'email-already-in-use',
      ),
      'weak-password' ||
      'password-does-not-meet-requirements' => const AuthenticationFailure(
        'Choose a stronger password that meets the account requirements.',
        code: 'weak-password',
      ),
      'account-exists-with-different-credential' => const AuthenticationFailure(
        'Use your existing sign-in method for this email address.',
        code: 'account-exists-with-different-credential',
      ),
      'invalid-email' => const AuthenticationFailure(
        'Enter a valid email address.',
        code: 'invalid-email',
      ),
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' => const AuthenticationFailure(
        'The email or password is incorrect.',
        code: 'invalid-credential',
      ),
      'user-disabled' => const AuthenticationFailure(
        'This account has been disabled. Contact FitNEP support.',
        code: 'user-disabled',
      ),
      'too-many-requests' => const AuthenticationFailure(
        'Too many sign-in attempts. Please wait and try again.',
        code: 'too-many-requests',
      ),
      'network-request-failed' => const AuthenticationFailure(
        'Check your connection and try again.',
        code: 'network-request-failed',
      ),
      'operation-not-allowed' => const AuthenticationFailure(
        'Email and password sign-in is not enabled for this Firebase project.',
        code: 'operation-not-allowed',
      ),
      _ => AuthenticationFailure(
        'We couldn\u2019t sign you in. Please try again.',
        code: error.code,
      ),
    };
  }
}
