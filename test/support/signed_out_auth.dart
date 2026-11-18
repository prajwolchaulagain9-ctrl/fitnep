import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

class SignedOutAuth extends Fake implements FirebaseAuth {
  @override
  User? get currentUser => null;
  @override
  Stream<User?> authStateChanges() => Stream<User?>.value(null);
}
