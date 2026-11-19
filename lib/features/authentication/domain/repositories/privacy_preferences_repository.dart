import '../entities/privacy_preferences.dart';

abstract class PrivacyPreferencesRepository {
  Future<PrivacyPreferences> loadPreferences();

  Future<void> savePreferences(PrivacyPreferences preferences);
}
