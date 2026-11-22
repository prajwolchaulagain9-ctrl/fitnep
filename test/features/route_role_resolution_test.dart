import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitnep/app/routes/route_access_gate.dart';
import 'package:flutter_test/flutter_test.dart';

class _User extends Fake implements User {
  _User(this.claims, {this.onToken});
  final Map<String, dynamic> claims;
  final void Function()? onToken;
  @override
  String get uid => 'client-a';
  @override
  Future<IdTokenResult> getIdTokenResult([bool forceRefresh = false]) async {
    onToken?.call();
    return _Token(claims);
  }
}

class _Token extends Fake implements IdTokenResult {
  _Token(this.claims);
  @override
  final Map<String, dynamic> claims;
}

class _Auth extends Fake implements FirebaseAuth {
  User? user;
  @override
  User? get currentUser => user;
}

void main() {
  test(
    'verified registration enters as a client without a setup endpoint',
    () async {
      final user = _User({'email_verified': true});
      expect(
        await resolveVerifiedRole(user, _Auth()..user = user),
        FitNepRole.client,
      );
    },
  );

  test('signed roles, including staff, are preserved and normalized', () async {
    for (final role in FitNepRole.values) {
      final user = _User({
        'role': ' ${role.name.toUpperCase()} ',
        'email_verified': true,
      });
      expect(await resolveVerifiedRole(user, _Auth()..user = user), role);
    }
  });

  test(
    'unverified and unsupported roles do not default to client access',
    () async {
      for (final claims in <Map<String, dynamic>>[
        {},
        {'email_verified': false},
        {'email_verified': 'true'},
        for (final role in [
          null,
          'owner',
          '',
          1,
          ['admin'],
        ])
          {'role': role, 'email_verified': true},
      ]) {
        final user = _User(claims);
        expect(await resolveVerifiedRole(user, _Auth()..user = user), isNull);
      }
    },
  );

  test(
    'sign-out while reading a token prevents stale account access',
    () async {
      final auth = _Auth();
      final user = _User({
        'email_verified': true,
      }, onToken: () => auth.user = null);
      auth.user = user;
      expect(await resolveVerifiedRole(user, auth), isNull);
    },
  );
}
