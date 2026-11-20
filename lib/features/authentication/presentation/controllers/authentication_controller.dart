import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/firebase_providers.dart';
import '../../../../core/config/app_config.dart';
import '../../data/authentication_service.dart';
import '../../data/google_credential_provider.dart';
import '../../data/session_preference_store.dart';

final sessionPreferenceStoreProvider = Provider<SessionPreferenceStore>(
  (ref) => const SecureSessionPreferenceStore(),
);

final googleCredentialProvider = Provider<GoogleCredentialProvider>(
  (ref) => NativeGoogleCredentialProvider(),
);

final authenticationBootstrapProvider = FutureProvider<AuthenticationService>((
  ref,
) async {
  await ref.watch(firebaseInitializationProvider.future);
  final service = AuthenticationService(
    auth: ref.read(firebaseAuthProvider),
    sessionPreferences: ref.read(sessionPreferenceStoreProvider),
    googleCredentials: ref.read(googleCredentialProvider),
  );
  // The named emulator app has its own session; live Remember Me preferences
  // must not sign out a seeded local-demo account during startup.
  if (!AppConfig.useFirebaseEmulators) await service.restoreSession();
  return service;
}, retry: (retryCount, error) => null);

final authenticationStateProvider = StreamProvider<User?>((ref) async* {
  final service = await ref.watch(authenticationBootstrapProvider.future);
  yield* service.authStateChanges();
}, retry: (retryCount, error) => null);

final staffPasswordChangeRequiredProvider = FutureProvider<bool>((ref) async {
  final user = await ref.watch(authenticationStateProvider.future);
  if (user == null) return false;
  final token = await user.getIdTokenResult();
  return token.claims?['mustChangePassword'] == true;
}, retry: (retryCount, error) => null);

class AuthenticationActionState {
  const AuthenticationActionState({
    this.isLoading = false,
    this.errorMessage,
    this.isGoogleSignIn = false,
  });

  final bool isLoading;
  final String? errorMessage;
  final bool isGoogleSignIn;
}

class AuthenticationController extends Notifier<AuthenticationActionState> {
  @override
  AuthenticationActionState build() => const AuthenticationActionState();

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
      // Refresh from Firebase if the stream still has the old session.
      if (ref.read(authenticationStateProvider).value != null) {
        ref.invalidate(authenticationStateProvider);
        await ref.read(authenticationStateProvider.future);
      }
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
  }) async {
    return _run(() async {
      final service = await ref.read(authenticationBootstrapProvider.future);
      await service.signUp(name: name, email: email, password: password);
      return true;
    });
  }

  Future<bool> signInWithGoogle({required bool rememberSession}) async {
    return _run(() async {
      final service = await ref.read(authenticationBootstrapProvider.future);
      return service.signInWithGoogle(rememberSession: rememberSession);
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
      if (ref.mounted) state = const AuthenticationActionState();
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
