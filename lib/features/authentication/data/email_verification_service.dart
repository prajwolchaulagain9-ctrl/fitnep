import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/firebase_providers.dart';
import '../../../shared/app_config.dart';
import 'authentication_service.dart';
import 'hosted_auth_client.dart';

final emailVerificationServiceProvider = Provider<EmailVerificationService>(
  (ref) => EmailVerificationService(
    auth: ref.read(firebaseAuthProvider),
    functions: ref.read(firebaseFunctionsProvider),
    sendUrl: AppConfig.signupOtpSendUrl,
    verifyUrl: AppConfig.signupOtpVerifyUrl,
    hostedRequest: AppConfig.hostedSessionsEnabled
        ? ref.read(hostedAuthRequestProvider)
        : null,
    useLinkByDefault:
        AppConfig.useFirebaseEmulators ||
        !AppConfig.signupEmailOtpEnabled ||
        (!AppConfig.hostedSessionsEnabled &&
            AppConfig.signupOtpSendUrl.isEmpty &&
            AppConfig.signupOtpVerifyUrl.isEmpty &&
            !(kDebugMode && AppConfig.functionsEmulatorHost.isNotEmpty)),
  ),
);

class EmailCodeDelivery {
  const EmailCodeDelivery({
    required this.resendAfterSeconds,
    this.emailVerified = false,
    this.usesVerificationLink = false,
  });
  final int resendAfterSeconds;
  final bool emailVerified;
  final bool usesVerificationLink;
}

class EmailVerificationFailure extends AuthenticationFailure {
  const EmailVerificationFailure(
    super.message, {
    super.code,
    this.retryAfterSeconds,
  });
  final int? retryAfterSeconds;
}

class EmailVerificationService {
  const EmailVerificationService({
    required this.auth,
    required this.functions,
    this.sendUrl = '',
    this.verifyUrl = '',
    this.useLinkByDefault = false,
    this.hostedRequest,
  });
  final FirebaseAuth auth;
  final FirebaseFunctions functions;
  final String sendUrl;
  final String verifyUrl;
  final bool useLinkByDefault;
  final HostedAuthRequest? hostedRequest;

  HttpsCallable _callable(String name, String configuredUrl) {
    if (sendUrl.isEmpty != verifyUrl.isEmpty) {
      throw const AuthenticationFailure(
        'Email verification is unavailable. Please try again later.',
      );
    }
    if (configuredUrl.isEmpty) return functions.httpsCallable(name);
    for (final url in [sendUrl, verifyUrl]) {
      final uri = Uri.tryParse(url);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw const AuthenticationFailure(
          'Email verification is unavailable. Please try again later.',
        );
      }
    }
    // Firebase's callable client supplies the current Firebase ID token to the
    // trusted serverless URL; API keys and admin credentials stay on that host.
    return functions.httpsCallableFromUrl(configuredUrl);
  }

  Future<EmailCodeDelivery> sendCode({bool resend = false}) async {
    if (useLinkByDefault) return sendVerificationLink();
    final user = _signedInUser();
    try {
      // The server derives UID and email from the authenticated session.
      final Object? data = hostedRequest != null
          ? await hostedRequest!('auth/signup/otp/send', {'resend': resend})
          : (await _callable(
              'sendSignupEmailCode',
              sendUrl,
            ).call({'resend': resend})).data;
      final seconds = data is Map ? data['resendAfterSeconds'] : null;
      if (seconds is! num || seconds < 0 || seconds > 3600) {
        throw const AuthenticationFailure(
          'We couldn\u2019t confirm delivery of your code. Please try again.',
        );
      }
      final alreadyVerified = data is Map && data['emailVerified'] == true;
      if (alreadyVerified) await _refreshVerifiedUser(user);
      return EmailCodeDelivery(
        resendAfterSeconds: seconds.toInt(),
        emailVerified: alreadyVerified,
      );
    } on AuthenticationFailure {
      rethrow;
    } on FirebaseFunctionsException catch (error) {
      if (const {
        'not-found',
        'unimplemented',
        'failed-precondition',
      }.contains(error.code)) {
        return sendVerificationLink();
      }
      throw _failure(error);
    } catch (_) {
      throw const AuthenticationFailure(
        'We couldn\u2019t send your code. Check your connection and try again.',
      );
    }
  }

  Future<EmailCodeDelivery> sendVerificationLink() async {
    final user = _signedInUser();
    try {
      final alreadyVerified = await _reloadVerification(user);
      if (!alreadyVerified) await user.sendEmailVerification();
      return EmailCodeDelivery(
        resendAfterSeconds: alreadyVerified ? 0 : 60,
        emailVerified: alreadyVerified,
        usesVerificationLink: true,
      );
    } on FirebaseAuthException catch (error) {
      throw AuthenticationService.failureFor(error);
    }
  }

  Future<bool> checkVerificationLink() async {
    try {
      return await _reloadVerification(_signedInUser());
    } on FirebaseAuthException catch (error) {
      throw AuthenticationService.failureFor(error);
    }
  }

  Future<void> verifyCode(String code) async {
    if (!RegExp(r'^\d{6}$').hasMatch(code.trim())) {
      throw const AuthenticationFailure(
        'Enter the 6-digit code from your email.',
      );
    }
    final user = _signedInUser();
    try {
      final Object? data = hostedRequest != null
          ? await hostedRequest!('auth/signup/otp/verify', {
              'code': code.trim(),
            })
          : (await _callable(
              'verifySignupEmailCode',
              verifyUrl,
            ).call({'code': code.trim()})).data;
      if (data is! Map || data['verified'] != true) {
        throw const AuthenticationFailure(
          'We couldn\u2019t confirm email verification. Please try again.',
        );
      }
      // Both User.emailVerified and the token claim must reflect the server update.
      await _refreshVerifiedUser(user);
    } on AuthenticationFailure {
      rethrow;
    } on FirebaseFunctionsException catch (error) {
      throw _failure(error);
    } catch (_) {
      throw const AuthenticationFailure(
        'We couldn\u2019t verify your email. Check your connection and try again.',
      );
    }
  }

  User _signedInUser() {
    final user = auth.currentUser;
    if (user == null) {
      throw const AuthenticationFailure(
        'Please log in again to verify your email.',
      );
    }
    return user;
  }

  Future<void> _refreshVerifiedUser(User user) async {
    if (!await _reloadVerification(user)) {
      throw const AuthenticationFailure(
        'We couldn\u2019t refresh your verification. Please try again.',
      );
    }
  }

  Future<bool> _reloadVerification(User user) async {
    if (auth.currentUser?.uid != user.uid) {
      throw const AuthenticationFailure(
        'Your account changed. Please log in again.',
      );
    }
    await user.reload();
    final refreshed = auth.currentUser;
    if (refreshed?.uid != user.uid) {
      throw const AuthenticationFailure(
        'Your account changed. Please log in again.',
      );
    }
    if (!refreshed!.emailVerified) return false;
    final token = await refreshed.getIdTokenResult(true);
    if (auth.currentUser?.uid != user.uid ||
        token.claims?['email_verified'] != true) {
      throw const AuthenticationFailure(
        'We couldn\u2019t refresh your verification. Please try again.',
      );
    }
    return true;
  }

  static EmailVerificationFailure _failure(FirebaseFunctionsException error) {
    final details = error.details;
    final seconds = details is Map ? details['retryAfterSeconds'] : null;
    final reason = details is Map ? details['reason'] : null;
    return EmailVerificationFailure(
      switch (error.code) {
        'invalid-argument' => 'That code is incorrect. Please try again.',
        'deadline-exceeded' => 'Your code has expired. Request a new code.',
        'resource-exhausted' =>
          reason == 'attempt-limit'
              ? 'Too many incorrect codes. Request a new code.'
              : 'Please wait before requesting another code.',
        'unauthenticated' => 'Please log in again to verify your email.',
        'failed-precondition' =>
          'Email verification is unavailable. Please try again later.',
        _ => 'We couldn\u2019t complete email verification. Please try again.',
      },
      code: error.code,
      retryAfterSeconds: seconds is num ? seconds.toInt().clamp(0, 3600) : null,
    );
  }
}
