import '../entities/privacy_preferences.dart';

abstract class PrivacyPreferencesRepository {
  Future<PrivacyPreferences> loadPreferences();

  Future<PrivacyPreferences> savePreferences(PrivacyPreferences preferences);
}
