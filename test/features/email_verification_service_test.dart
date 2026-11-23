import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitnep/features/authentication/data/authentication_service.dart';
import 'package:fitnep/features/authentication/data/email_verification_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _User extends Fake implements User {
  _User([this.uid = 'client-a']);
  @override
  final String uid;
  @override
  bool emailVerified = false;
  int reloads = 0;
  int tokenRefreshes = 0;
  int verificationLinksSent = 0;
  bool verifiedOnReload = true;
  bool verifiedTokenClaim = true;
  @override
  Future<void> reload() async {
    reloads++;
    emailVerified = verifiedOnReload;
  }

  @override
  Future<void> sendEmailVerification([
    ActionCodeSettings? actionCodeSettings,
  ]) async {
    verificationLinksSent++;
  }

  @override
  Future<IdTokenResult> getIdTokenResult([bool forceRefresh = false]) async {
    expect(forceRefresh, isTrue);
    tokenRefreshes++;
    return _TokenResult(verifiedTokenClaim);
  }
}

class _TokenResult extends Fake implements IdTokenResult {
  _TokenResult(this.verified);
  final bool verified;
  @override
  Map<String, dynamic> get claims => {'email_verified': verified};
}

class _Auth extends Fake implements FirebaseAuth {
  User? user;
  @override
  User? get currentUser => user;
}

class _Result<T> extends Fake implements HttpsCallableResult<T> {
  _Result(this.data);
  @override
  final T data;
}

class _Callable extends Fake implements HttpsCallable {
  dynamic response;
  FirebaseFunctionsException? error;
  Object? parameters;
  int calls = 0;
  void Function()? onCall;
  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async {
    calls++;
    this.parameters = parameters;
    onCall?.call();
    if (error != null) throw error!;
    return _Result<T>(response as T);
  }
}

class _Functions extends Fake implements FirebaseFunctions {
  final send = _Callable()..response = {'resendAfterSeconds': 60};
  final verify = _Callable()..response = {'verified': true};
  final urls = <String>[];
  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      name == 'sendSignupEmailCode' ? send : verify;
  @override
  HttpsCallable httpsCallableFromUrl(
    String url, {
    HttpsCallableOptions? options,
  }) {
    urls.add(url);
    return url.endsWith('/send') ? send : verify;
  }
}

void main() {
  late _Auth auth;
  late _User user;
  late _Functions functions;
  late EmailVerificationService service;
  setUp(() {
    user = _User();
    auth = _Auth()..user = user;
    functions = _Functions();
    service = EmailVerificationService(auth: auth, functions: functions);
  });

  test(
    'initial send and explicit resend never supply a client UID or email',
    () async {
      final delivery = await service.sendCode();
      expect(delivery.resendAfterSeconds, 60);
      expect(functions.send.parameters, {'resend': false});
      await service.sendCode(resend: true);
      expect(functions.send.parameters, {'resend': true});
    },
  );

  test(
    'falls back to a Firebase link when hosted codes are unavailable',
    () async {
      user.verifiedOnReload = false;
      service = EmailVerificationService(
        auth: auth,
        functions: functions,
        hostedRequest: (path, data) async {
          expect(path, 'auth/signup/otp/send');
          expect(data, {'resend': false});
          throw FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'Code delivery is not configured.',
          );
        },
      );

      final delivery = await service.sendCode();
      expect(delivery.usesVerificationLink, isTrue);
      expect(delivery.emailVerified, isFalse);
      expect(user.verificationLinksSent, 1);
      expect(await service.checkVerificationLink(), isFalse);

      user.verifiedOnReload = true;
      expect(await service.checkVerificationLink(), isTrue);
      expect(user.tokenRefreshes, 1);
    },
  );

  test(
    'invalid delivery responses cannot confirm that a code was sent',
    () async {
      for (final invalid in [
        null,
        {},
        {'resendAfterSeconds': -1},
        {'resendAfterSeconds': '60'},
      ]) {
        functions.send.response = invalid;
        await expectLater(
          service.sendCode(),
          throwsA(isA<AuthenticationFailure>()),
        );
      }
    },
  );

  test('a server cooldown provides the remaining resend time', () async {
    functions.send.error = FirebaseFunctionsException(
      code: 'resource-exhausted',
      message: 'Wait before requesting another code.',
      details: {'reason': 'resend-cooldown', 'retryAfterSeconds': 42},
    );
    await expectLater(
      service.sendCode(),
      throwsA(
        isA<EmailVerificationFailure>().having(
          (error) => error.retryAfterSeconds,
          'retryAfterSeconds',
          42,
        ),
      ),
    );
  });

  test('verification requires the server result and refreshes Firebase user and token', () async {
    await service.verifyCode('123456');
    expect(functions.verify.parameters, {'code': '123456'});
    expect(user.reloads, 1);
    expect(user.tokenRefreshes, 1);
    expect(user.emailVerified, isTrue);
  });

  test('verification cannot complete for a different account', () async {
    functions.verify.onCall = () => auth.user = _User('client-b');
    await expectLater(
      service.verifyCode('123456'),
      throwsA(isA<AuthenticationFailure>()),
    );
    expect(user.reloads, 0);
    expect(user.tokenRefreshes, 0);
  });

  test(
    'false verification and unverified refreshed users cannot unlock the app',
    () async {
      functions.verify.response = {'verified': false};
      await expectLater(
        service.verifyCode('123456'),
        throwsA(isA<AuthenticationFailure>()),
      );
      expect(user.reloads, 0);
      functions.verify.response = {'verified': true};
      user.verifiedOnReload = false;
      await expectLater(
        service.verifyCode('123456'),
        throwsA(isA<AuthenticationFailure>()),
      );
      expect(user.emailVerified, isFalse);
    },
  );

  test(
    'already verified accounts reconcile a stale local Firebase user',
    () async {
      functions.send.response = {
        'emailVerified': true,
        'resendAfterSeconds': 0,
      };
      final result = await service.sendCode();
      expect(result.emailVerified, isTrue);
      expect(user.reloads, 1);
      expect(user.tokenRefreshes, 1);
    },
  );

  test(
    'invalid codes and missing sessions are rejected before any callable',
    () async {
      await expectLater(
        service.verifyCode('abc'),
        throwsA(isA<AuthenticationFailure>()),
      );
      auth.user = null;
      await expectLater(
        service.sendCode(),
        throwsA(isA<AuthenticationFailure>()),
      );
      await expectLater(
        service.verifyCode('123456'),
        throwsA(isA<AuthenticationFailure>()),
      );
      expect(functions.send.calls, 0);
      expect(functions.verify.calls, 0);
    },
  );

  test(
    'verification requires the refreshed token verification claim',
    () async {
      user.verifiedTokenClaim = false;
      await expectLater(
        service.verifyCode('123456'),
        throwsA(isA<AuthenticationFailure>()),
      );
      expect(user.emailVerified, isTrue);
      expect(user.tokenRefreshes, 1);
    },
  );

  test(
    'serverless endpoints retain the callable protocol and payloads',
    () async {
      service = EmailVerificationService(
        auth: auth,
        functions: functions,
        sendUrl: 'https://auth.example.test/send',
        verifyUrl: 'https://auth.example.test/verify',
      );
      await service.sendCode();
      await service.verifyCode('123456');
      expect(functions.urls, [
        'https://auth.example.test/send',
        'https://auth.example.test/verify',
      ]);
      expect(functions.send.parameters, {'resend': false});
      expect(functions.verify.parameters, {'code': '123456'});
    },
  );

  test(
    'both serverless endpoints must be present and secure before sending',
    () async {
      for (final urls in [
        ['https://auth.example.test/send', ''],
        ['https://auth.example.test/send', 'http://auth.example.test/verify'],
        [
          'https://name:secret@auth.example.test/send',
          'https://auth.example.test/verify',
        ],
      ]) {
        service = EmailVerificationService(
          auth: auth,
          functions: functions,
          sendUrl: urls[0],
          verifyUrl: urls[1],
        );
        await expectLater(
          service.sendCode(),
          throwsA(isA<AuthenticationFailure>()),
        );
      }
      expect(functions.send.calls, 0);
      expect(functions.urls, isEmpty);
    },
  );
}
