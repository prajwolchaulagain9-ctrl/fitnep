abstract final class AppConfig {
  // Match this to the region of the shared Functions deployment.
  static const functionsRegion = String.fromEnvironment(
    'FIREBASE_FUNCTIONS_REGION',
    defaultValue: 'us-central1',
  );
}
