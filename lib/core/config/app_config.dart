class AppConfig {
  AppConfig._();

  // Use a Firebase verification link if custom email codes are disabled.
  static const signupEmailOtpEnabled = bool.fromEnvironment(
    'SIGNUP_EMAIL_OTP_ENABLED',
    defaultValue: true,
  );
  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );
  static const googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
  );
  static const signupOtpSendUrl = String.fromEnvironment('SIGNUP_OTP_SEND_URL');
  static const signupOtpVerifyUrl = String.fromEnvironment(
    'SIGNUP_OTP_VERIFY_URL',
  );
  static const signupPrivacyUrl = String.fromEnvironment('SIGNUP_PRIVACY_URL');

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

  // Local development only; the SDK override is ignored in release builds.
  static const functionsEmulatorHost = String.fromEnvironment(
    'FIREBASE_FUNCTIONS_EMULATOR_HOST',
  );
  static const functionsEmulatorPort = int.fromEnvironment(
    'FIREBASE_FUNCTIONS_EMULATOR_PORT',
    defaultValue: 5001,
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
  static bool get hostedSessionsEnabled => hasApiBaseUrl && !useFirebaseEmulators;
}
