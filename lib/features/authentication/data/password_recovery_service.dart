import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/firebase_providers.dart';

final passwordRecoveryProvider = Provider<PasswordRecoveryService>(
  (ref) => PasswordRecoveryService(ref.watch(firebaseAuthProvider)),
);

class RecoveryFailure implements Exception {
  const RecoveryFailure(
    this.message, {
    this.invalidLink = false,
    this.passwordUpdated = false,
  });

  final String message;
  final bool invalidLink;
  final bool passwordUpdated;
}

class PasswordRecoveryService {
  PasswordRecoveryService(this.auth);

  final FirebaseAuth auth;

  static const requestConfirmation =
      'If an account uses this email, you will receive a password reset link. '
      'Check your inbox and spam folder.';

  static String? emailError(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Enter your registered email address.';
    if (email.length > 254 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  // Accept an email action link or its code; Firebase remains the authority
  // for the code's project, expiry and single-use validity.
  static String actionCode(String value) {
    final input = value.trim();
    final uri = Uri.tryParse(input);
    String? code;
    if (uri != null && uri.hasScheme) {
      final mode = uri.queryParametersAll['mode'];
      final codes = uri.queryParametersAll['oobCode'];
      if ((uri.scheme != 'https' && uri.scheme != 'fitnep') ||
          mode?.length != 1 ||
          mode!.single != 'resetPassword' ||
          codes?.length != 1) {
        throw const RecoveryFailure(
          'Use the password reset link from your email.',
          invalidLink: true,
        );
      }
      code = codes!.single;
    } else {
      code = input;
    }
    if (!RegExp(r'^[A-Za-z0-9_-]{6,2048}$').hasMatch(code)) {
      throw const RecoveryFailure(
        'This reset link is invalid. Request a new link.',
        invalidLink: true,
      );
    }
    return code;
  }

  Future<void> request(String email) async {
    final error = emailError(email);
    if (error != null) throw RecoveryFailure(error);
    try {
      await auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (error) {
      // Older projects can still return these without enumeration protection.
      if (error.code == 'user-not-found' || error.code == 'user-disabled') {
        return;
      }
      throw failureFor(error);
    }
  }

  Future<String> verify(String code) async {
    try {
      return await auth.verifyPasswordResetCode(actionCode(code));
    } on FirebaseAuthException catch (error) {
      throw failureFor(error);
    }
  }

  Future<void> confirm(String code, String password) async {
    if (password.isEmpty) {
      throw const RecoveryFailure('Enter your new password.');
    }
    try {
      final status = await auth.validatePassword(auth, password);
      if (!status.isValid) {
        final missing = <String>[
          if (!status.meetsMinPasswordLength) 'more characters',
          if (!status.meetsMaxPasswordLength) 'fewer characters',
          if (!status.meetsLowercaseRequirement) 'a lowercase letter',
          if (!status.meetsUppercaseRequirement) 'an uppercase letter',
          if (!status.meetsDigitsRequirement) 'a number',
          if (!status.meetsSymbolsRequirement) 'a special character',
        ];
        throw RecoveryFailure(
          missing.isEmpty
              ? 'Your password does not meet the account security requirements.'
              : 'Your password needs ${missing.join(', ')}.',
        );
      }
      await auth.confirmPasswordReset(
        code: actionCode(code),
        newPassword: password,
      );
    } on FirebaseAuthException catch (error) {
      throw failureFor(error);
    } on RecoveryFailure {
      rethrow;
    } catch (_) {
      throw const RecoveryFailure(
        'We couldn’t check your password requirements. Check your connection '
        'and try again.',
      );
    }
    await clearLocalSession();
  }

  Future<void> clearLocalSession() async {
    try {
      await auth.signOut();
    } catch (_) {
      // The reset code has already been consumed. Retry sign-out, not reset.
      throw const RecoveryFailure(
        'Your password was updated, but we couldn’t sign out this device. '
        'Please finish signing out before continuing.',
        passwordUpdated: true,
      );
    }
  }

  // Call from the shared session lifecycle on resume/refresh. This reports
  // whether an old session ended; it is not authorization for protected data.
  Future<bool> signOutIfSessionRevoked() async {
    final user = auth.currentUser;
    if (user == null) return false;
    try {
      await user.getIdToken(true);
      return false;
    } on FirebaseAuthException catch (error) {
      if (!const {
        'user-token-expired',
        'invalid-user-token',
        'user-disabled',
        'user-not-found',
      }.contains(error.code)) {
        rethrow;
      }
      // A different account may have signed in while refresh was in flight.
      if (auth.currentUser?.uid == user.uid) await auth.signOut();
      return true;
    }
  }

  static RecoveryFailure failureFor(FirebaseAuthException error) {
    return switch (error.code) {
      'expired-action-code' ||
      'invalid-action-code' ||
      'user-disabled' ||
      'user-not-found' => const RecoveryFailure(
        'This reset link has expired or was already used. Request a new link.',
        invalidLink: true,
      ),
      'weak-password' ||
      'password-does-not-meet-requirements' => const RecoveryFailure(
        'Choose a stronger password that meets your account requirements.',
      ),
      'too-many-requests' => const RecoveryFailure(
        'Too many attempts. Please wait a while before trying again.',
      ),
      'network-request-failed' => const RecoveryFailure(
        'Check your connection and try again.',
      ),
      'invalid-email' => const RecoveryFailure('Enter a valid email address.'),
      _ => const RecoveryFailure(
        'Password recovery is unavailable right now. Please try again later.',
      ),
    };
  }
}
