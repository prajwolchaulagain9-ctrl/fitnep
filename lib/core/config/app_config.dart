class AppConfig {
  AppConfig._();

  static const functionsRegion = String.fromEnvironment(
    'FIREBASE_FUNCTIONS_REGION',
    defaultValue: 'us-central1',
  );

  static const String _configuredApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static String get apiBaseUrl {
    final value = _configuredApiBaseUrl.trim();
    if (value.isEmpty || value.endsWith('/')) return value;
    return '$value/';
  }

  static bool get hasApiBaseUrl => apiBaseUrl.isNotEmpty;
}
