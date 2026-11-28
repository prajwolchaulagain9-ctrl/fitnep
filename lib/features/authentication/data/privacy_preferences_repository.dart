import 'privacy_preferences.dart';

abstract class PrivacyPreferencesRepository {
  Future<PrivacyPreferences> loadPreferences();

  Future<PrivacyPreferences> setSharing(
    PrivacySharingCategory category,
    bool enabled,
  );
}
