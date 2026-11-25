import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/firebase_providers.dart';
import '../../../../core/config/app_config.dart';
import '../../data/authentication_service.dart';
import '../../data/google_credential_provider.dart';
import '../../data/session_preference_store.dart';
import '../../data/hosted_session_service.dart';
import '../../data/registration_privacy.dart';
import '../../data/hosted_auth_client.dart';
import '../../domain/entities/privacy_policy.dart';
import '../../../../core/network/api_client_provider.dart';

final sessionPreferenceStoreProvider = Provider<SessionPreferenceStore>(
  (ref) => const SecureSessionPreferenceStore(),
);

final googleCredentialProvider = Provider<GoogleCredentialProvider>(
  (ref) => NativeGoogleCredentialProvider(),
);

final googlePasswordSetupProvider = Provider<Future<void> Function()?>((ref) {
  if (!ref.watch(hostedSessionServiceProvider).enabled) return null;
  return () async {
    try {
      final result = await ref.read(hostedAuthRequestProvider)(
        'auth/google/email-password',
        {},
      );
      if (result['email_sent'] == true &&
          result['already_sent'] != true &&
          ref.mounted) {
        ref
            .read(authenticationControllerProvider.notifier)
            .reportNotice(
              'Your temporary password was emailed to you. You can use email login and choose your own password.',
            );
      }
    } on FirebaseFunctionsException {
      if (ref.mounted) {
        ref
            .read(authenticationControllerProvider.notifier)
            .reportNotice(
              'Google sign-in worked, but we couldn’t email your temporary password. Try Google sign-in again to retry delivery.',
            );
      }
    }
  };
});

final authenticationBootstrapProvider = FutureProvider<AuthenticationService>((
  ref,
) async {
  await ref.watch(firebaseInitializationProvider.future);
  final service = AuthenticationService(
    auth: ref.read(firebaseAuthProvider),
    sessionPreferences: ref.read(sessionPreferenceStoreProvider),
    googleCredentials: ref.read(googleCredentialProvider),
    beforeSignOut: ref.read(hostedSessionServiceProvider).end,
    afterGoogleSignIn: ref.read(googlePasswordSetupProvider),
  );
  // The named emulator app has its own session; live Remember Me preferences
  // must not sign out a seeded local-demo account during startup.
  if (!AppConfig.useFirebaseEmulators) await service.restoreSession();
  if (AppConfig.hostedSessionsEnabled) {
    // Network failure keeps pending logout encrypted for a later retry.
    try {
      await ref.read(hostedSessionServiceProvider).reconcileLogout();
    } catch (_) {}
  }
  return service;
}, retry: (retryCount, error) => null);

// Firebase publishes the first Google identity before password delivery refreshes
// its credential. Account/consent requests must wait for that refresh to finish.
final authenticationSettledProvider = FutureProvider<void>((ref) async {
  if (!ref.watch(
    authenticationControllerProvider.select((action) => action.isLoading),
  )) {
    return;
  }
  await Completer<void>().future;
});

final staffPasswordChangeRequiredProvider = FutureProvider<bool>((ref) async {
  await ref.watch(authenticationSettledProvider.future);
  final user = await ref.watch(authenticationStateProvider.future);
  if (user == null) return false;
  if (AppConfig.hostedSessionsEnabled) {
    final response = await ref
        .watch(apiClientProvider)
        .dio
        .get<Map<String, dynamic>>('session')
        .timeout(const Duration(seconds: 65));
    return (response.data?['data'] as Map?)?['must_change_password'] == true;
  }
  final token = await user.getIdTokenResult();
  return token.claims?['mustChangePassword'] == true ||
      token.claims?['must_change_password'] == true;
}, retry: (count, error) => null);

final authenticationStateProvider = StreamProvider<User?>((ref) async* {
  final service = await ref.watch(authenticationBootstrapProvider.future);
  yield* service.authStateChanges();
}, retry: (retryCount, error) => null);

class AuthenticationActionState {
  const AuthenticationActionState({
    this.isLoading = false,
    this.errorMessage,
    this.isGoogleSignIn = false,
    this.noticeMessage,
  });

  final bool isLoading;
  final String? errorMessage;
  final bool isGoogleSignIn;
  final String? noticeMessage;
}

class AuthenticationController extends Notifier<AuthenticationActionState> {
  @override
  AuthenticationActionState build() => const AuthenticationActionState();

  void reportNotice(String message) {
    state = AuthenticationActionState(
      isLoading: state.isLoading,
      isGoogleSignIn: state.isGoogleSignIn,
      noticeMessage: message,
    );
  }

  Future<bool> signIn({
    required String email,
    required String password,
    required bool rememberSession,
  }) async {
    if (state.isLoading) return false;
    state = const AuthenticationActionState(isLoading: true);

    try {
      final service = await ref.read(authenticationBootstrapProvider.future);
      await service.signIn(
        email: email,
        password: password,
        rememberSession: rememberSession,
      );
      state = const AuthenticationActionState();
      return true;
    } on AuthenticationFailure catch (error) {
      state = AuthenticationActionState(errorMessage: error.message);
      return false;
    } catch (_) {
      state = const AuthenticationActionState(
        errorMessage: 'We couldn\u2019t sign you in. Please try again.',
      );
      return false;
    }
  }

  Future<bool> signOut() async {
    if (state.isLoading) return false;
    state = const AuthenticationActionState(isLoading: true);

    try {
      final service = await ref.read(authenticationBootstrapProvider.future);
      await service.signOut();
      ref.invalidate(authenticationStateProvider);
      await ref.read(authenticationStateProvider.future);
      state = const AuthenticationActionState();
      return true;
    } on AuthenticationFailure catch (error) {
      state = AuthenticationActionState(errorMessage: error.message);
      return false;
    } catch (_) {
      state = const AuthenticationActionState(
        errorMessage: 'We couldn\u2019t sign you out. Please try again.',
      );
      return false;
    }
  }

  Future<bool> signUp({
    required String name,
    required String email,
    required String password,
    RegistrationConsent? consent,
  }) async {
    return _run(() async {
      final service = await ref.read(authenticationBootstrapProvider.future);
      final uid = await service.signUp(
        name: name,
        email: email,
        password: password,
      );
      if (uid != null && consent != null && ref.mounted) {
        try {
          await ref
              .read(pendingRegistrationConsentStoreProvider)
              .write(uid, consent);
        } catch (_) {}
      }
      return true;
    });
  }

  Future<bool> signInWithGoogle({
    required bool rememberSession,
    RegistrationConsent? consent,
  }) async {
    return _run(() async {
      final service = await ref.read(authenticationBootstrapProvider.future);
      final signedIn = await service.signInWithGoogle(
        rememberSession: rememberSession,
      );
      final uid = service.auth.currentUser?.uid;
      if (signedIn && uid != null && consent != null && ref.mounted) {
        await ref
            .read(pendingRegistrationConsentStoreProvider)
            .write(uid, consent);
        ref.invalidate(registrationAcceptedProvider(uid));
      }
      return signedIn;
    }, google: true);
  }

  Future<bool> _run(
    Future<bool> Function() action, {
    bool google = false,
  }) async {
    if (state.isLoading) return false;
    state = AuthenticationActionState(isLoading: true, isGoogleSignIn: google);
    try {
      final succeeded = await action();
      if (ref.mounted) {
        state = AuthenticationActionState(noticeMessage: state.noticeMessage);
      }
      return succeeded;
    } on AuthenticationFailure catch (error) {
      if (ref.mounted) {
        state = AuthenticationActionState(errorMessage: error.message);
      }
    } catch (_) {
      if (ref.mounted) {
        state = const AuthenticationActionState(
          errorMessage: 'We couldn\u2019t complete sign-in. Please try again.',
        );
      }
    }
    return false;
  }

  void clearError() {
    if (!state.isLoading && state.errorMessage != null) {
      state = const AuthenticationActionState();
    }
  }
}

final authenticationControllerProvider =
    NotifierProvider<AuthenticationController, AuthenticationActionState>(
      AuthenticationController.new,
    );
