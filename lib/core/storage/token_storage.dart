import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  static const _accessTokenKey = 'access_token';

  final FlutterSecureStorage _storage;
  final FirebaseAuth? auth;

  const TokenStorage({this.auth}) : _storage = const FlutterSecureStorage();

  Future<String?> readAccessToken() async {
    final currentAuth = auth;
    if (currentAuth != null) return currentAuth.currentUser?.getIdToken();
    return _storage.read(key: _accessTokenKey);
  }

  Future<void> writeAccessToken(String token) =>
      _storage.write(key: _accessTokenKey, value: token);

  Future<void> deleteAccessToken() => _storage.delete(key: _accessTokenKey);
}
