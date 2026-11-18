import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitnep/features/authentication/data/password_recovery_service.dart';
import 'package:flutter_test/flutter_test.dart';

class TestPasswordStatus extends Fake implements PasswordValidationStatus {
  TestPasswordStatus({this.isValid = true});

  @override
  final bool isValid;
  @override
  bool get meetsMinPasswordLength => isValid;
  @override
  bool get meetsMaxPasswordLength => true;
  @override
  bool get meetsLowercaseRequirement => true;
  @override
  bool get meetsUppercaseRequirement => isValid;
  @override
  bool get meetsDigitsRequirement => true;
  @override
  bool get meetsSymbolsRequirement => true;
}

class TestRecoveryAuth extends Fake implements FirebaseAuth {
  FirebaseAuthException? requestError;
  FirebaseAuthException? codeError;
  FirebaseAuthException? confirmError;
  bool strongPassword = true;
  bool used = false;
  bool policyOffline = false;
  bool signOutFails = false;
  int signOuts = 0;
  String? requestedEmail;
  String? confirmedPassword;

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    ActionCodeSettings? actionCodeSettings,
  }) async {
    requestedEmail = email;
    if (requestError != null) throw requestError!;
  }

  @override
  Future<String> verifyPasswordResetCode(String code) async {
    if (codeError != null) throw codeError!;
    if (used) throw FirebaseAuthException(code: 'invalid-action-code');
    return 'client@example.com';
  }

  @override
  Future<PasswordValidationStatus> validatePassword(
    FirebaseAuth auth,
    String? password,
  ) async {
    if (policyOffline) throw StateError('Network failure');
    return TestPasswordStatus(isValid: strongPassword);
  }

  @override
  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  }) async {
    if (confirmError != null) throw confirmError!;
    if (used) throw FirebaseAuthException(code: 'invalid-action-code');
    used = true;
    confirmedPassword = newPassword;
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    if (signOutFails) throw StateError('Device sign-out failed');
  }
}

void main() {
  late TestRecoveryAuth auth;
  late PasswordRecoveryService service;
  setUp(() {
    auth = TestRecoveryAuth();
    service = PasswordRecoveryService(auth);
  });

  test(
    'cleanup failure preserves successful reset and retries only sign-out',
    () async {
      auth.signOutFails = true;
      await expectLater(
        service.confirm('valid_code', 'Stronger!12'),
        throwsA(
          isA<RecoveryFailure>().having(
            (e) => e.passwordUpdated,
            'reset succeeded',
            true,
          ),
        ),
      );
      expect(auth.used, isTrue);
      auth.signOutFails = false;
      await service.clearLocalSession();
      expect(auth.signOuts, 2);
      expect(auth.confirmedPassword, 'Stronger!12');
    },
  );

  test('registered and missing emails return equivalent completion', () async {
    await service.request('  client@example.com  ');
    expect(auth.requestedEmail, 'client@example.com');
    auth.requestError = FirebaseAuthException(code: 'user-not-found');
    await service.request('missing@example.com');
    auth.requestError = FirebaseAuthException(code: 'user-disabled');
    await service.request('disabled@example.com');
  });

  test(
    'malformed email never sends and offline delivery remains retryable',
    () async {
      await expectLater(
        service.request('invalid'),
        throwsA(isA<RecoveryFailure>()),
      );
      expect(auth.requestedEmail, isNull);
      auth.requestError = FirebaseAuthException(code: 'network-request-failed');
      await expectLater(
        service.request('client@example.com'),
        throwsA(
          isA<RecoveryFailure>().having(
            (e) => e.invalidLink,
            'retryable',
            false,
          ),
        ),
      );
    },
  );

  test(
    'links accept one reset code and reject other actions and duplicates',
    () {
      expect(
        PasswordRecoveryService.actionCode(
          'https://fitnep-88908.firebaseapp.com/__/auth/action?mode=resetPassword&oobCode=valid_code',
        ),
        'valid_code',
      );
      for (final link in [
        'https://example.com/?mode=verifyEmail&oobCode=valid_code',
        'https://example.com/?mode=resetPassword&oobCode=valid_code&oobCode=another_code',
        'javascript:alert(1)',
        'short',
      ]) {
        expect(
          () => PasswordRecoveryService.actionCode(link),
          throwsA(isA<RecoveryFailure>()),
        );
      }
    },
  );

  test(
    'expired code is terminal and network verification is retryable',
    () async {
      auth.codeError = FirebaseAuthException(code: 'expired-action-code');
      await expectLater(
        service.verify('valid_code'),
        throwsA(
          isA<RecoveryFailure>().having((e) => e.invalidLink, 'expired', true),
        ),
      );
      auth.codeError = FirebaseAuthException(code: 'network-request-failed');
      await expectLater(
        service.verify('valid_code'),
        throwsA(
          isA<RecoveryFailure>().having(
            (e) => e.invalidLink,
            'retryable',
            false,
          ),
        ),
      );
    },
  );

  test(
    'policy failures explain missing requirements before consuming code',
    () async {
      auth.strongPassword = false;
      await expectLater(
        service.confirm('valid_code', 'weak'),
        throwsA(
          isA<RecoveryFailure>().having(
            (e) => e.message,
            'explanation',
            contains('uppercase'),
          ),
        ),
      );
      expect(auth.used, isFalse);
      auth.strongPassword = true;
      auth.policyOffline = true;
      await expectLater(
        service.confirm('valid_code', 'Stronger!12'),
        throwsA(isA<RecoveryFailure>()),
      );
      expect(auth.used, isFalse);
    },
  );

  test(
    'server policy rejection is handled and successful code cannot replay',
    () async {
      auth.confirmError = FirebaseAuthException(
        code: 'password-does-not-meet-requirements',
      );
      await expectLater(
        service.confirm('valid_code', 'Stronger!12'),
        throwsA(isA<RecoveryFailure>()),
      );
      auth.confirmError = null;
      await service.confirm('valid_code', '  Stronger!12  ');
      expect(auth.confirmedPassword, '  Stronger!12  ');
      expect(auth.signOuts, 1);
      await expectLater(
        service.confirm('valid_code', 'Different!12'),
        throwsA(
          isA<RecoveryFailure>().having((e) => e.invalidLink, 'used', true),
        ),
      );
    },
  );
}
