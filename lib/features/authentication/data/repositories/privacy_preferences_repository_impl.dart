import '../../domain/entities/privacy_preferences.dart';
import '../../domain/repositories/privacy_preferences_repository.dart';
import '../datasources/privacy_preferences_local_datasource.dart';

class PrivacyPreferencesRepositoryImpl implements PrivacyPreferencesRepository {
  final PrivacyPreferencesLocalDatasource _localDatasource;

  const PrivacyPreferencesRepositoryImpl(this._localDatasource);

  @override
  Future<PrivacyPreferences> loadPreferences() =>
      _localDatasource.readPreferences();

  @override
  Future<void> savePreferences(PrivacyPreferences preferences) =>
      _localDatasource.writePreferences(preferences);
}
