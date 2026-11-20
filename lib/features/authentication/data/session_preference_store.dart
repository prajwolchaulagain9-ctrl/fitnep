import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SessionPreferenceStore {
  Future<bool?> readRememberSession();

  Future<void> writeRememberSession(bool rememberSession);

  Future<void> clearRememberSession();
}

class SecureSessionPreferenceStore implements SessionPreferenceStore {
  const SecureSessionPreferenceStore({
    this._storage = const FlutterSecureStorage(),
  });

  static const _rememberSessionKey = 'remember_authenticated_session';

  final FlutterSecureStorage _storage;

  @override
  Future<bool?> readRememberSession() async {
    return switch (await _storage.read(key: _rememberSessionKey)) {
      'true' => true,
      'false' => false,
      _ => null,
    };
  }

  @override
  Future<void> writeRememberSession(bool rememberSession) {
    return _storage.write(
      key: _rememberSessionKey,
      value: rememberSession.toString(),
    );
  }

  @override
  Future<void> clearRememberSession() {
    return _storage.delete(key: _rememberSessionKey);
  }
}
