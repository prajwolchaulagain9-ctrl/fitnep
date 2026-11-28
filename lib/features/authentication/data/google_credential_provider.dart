import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../shared/app_config.dart';
import 'authentication_service.dart';

abstract interface class GoogleCredentialProvider {
  Future<AuthCredential?> authenticate();
}

class NativeGoogleCredentialProvider implements GoogleCredentialProvider {
  static Future<void>? _initialization;

  Future<void> _initialize() async {
    try {
      await (_initialization ??= GoogleSignIn.instance.initialize(
        clientId:
            defaultTargetPlatform != TargetPlatform.iOS ||
                AppConfig.googleIosClientId.isEmpty
            ? null
            : AppConfig.googleIosClientId,
        serverClientId: AppConfig.googleWebClientId.isEmpty
            ? null
            : AppConfig.googleWebClientId,
      ));
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }

  @override
  Future<AuthCredential?> authenticate() async {
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      throw const AuthenticationFailure(
        'Google sign-in is available on Android and iOS.',
        code: 'unsupported-platform',
      );
    }
    try {
      await _initialize();
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const AuthenticationFailure(
          'Google could not verify your account. Please try again.',
        );
      }
      return GoogleAuthProvider.credential(idToken: idToken);
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) return null;
      throw AuthenticationFailure(
        error.code == GoogleSignInExceptionCode.clientConfigurationError ||
                error.code ==
                    GoogleSignInExceptionCode.providerConfigurationError
            ? 'Google sign-in is unavailable right now. Please use email instead.'
            : 'We couldn\u2019t connect to Google. Please try again.',
        code: error.code.name,
      );
    }
  }
}
