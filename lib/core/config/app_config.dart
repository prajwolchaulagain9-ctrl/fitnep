class AppConfig {
  AppConfig._();

  static const useFirebaseEmulators = bool.fromEnvironment(
    'USE_FIREBASE_EMULATORS',
  );
  static const emulatorHost = String.fromEnvironment(
    'FIREBASE_EMULATOR_HOST',
    defaultValue: '127.0.0.1',
  );

  static const functionsRegion = String.fromEnvironment(
    'FIREBASE_FUNCTIONS_REGION',
    defaultValue: 'us-central1',
  );

  static const String _configuredApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static String get apiBaseUrl {
    if (useFirebaseEmulators) return 'http://$emulatorHost:3000/';
    final value = _configuredApiBaseUrl.trim();
    if (value.isEmpty || value.endsWith('/')) return value;
    return '$value/';
  }

  static bool get hasApiBaseUrl => apiBaseUrl.isNotEmpty;
}
