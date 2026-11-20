import '../../../../core/network/api_client.dart';
import '../../domain/entities/privacy_preferences.dart';
import '../../domain/repositories/privacy_preferences_repository.dart';

class PrivacyPreferencesRepositoryImpl implements PrivacyPreferencesRepository {
  static const _endpoint = 'privacy/preferences';
  final ApiClient _apiClient;

  const PrivacyPreferencesRepositoryImpl(this._apiClient);

  @override
  Future<PrivacyPreferences> loadPreferences() async {
    _ensureConfigured();
    final response = await _apiClient.dio.get<Object?>(_endpoint);
    return _decodePreferences(response.data);
  }

  @override
  Future<PrivacyPreferences> savePreferences(
    PrivacyPreferences preferences,
  ) async {
    _ensureConfigured();
    final response = await _apiClient.dio.patch<Object?>(
      _endpoint,
      data: {'share_nutrition_records': preferences.shareNutritionRecords},
    );
    return _decodePreferences(response.data);
  }

  void _ensureConfigured() {
    if (_apiClient.dio.options.baseUrl.trim().isEmpty) {
      throw StateError('The privacy preferences service is not configured.');
    }
  }

  PrivacyPreferences _decodePreferences(Object? body) {
    if (body case {
      'data': {'preferences': {'share_nutrition_records': final bool enabled}},
    }) {
      return PrivacyPreferences(shareNutritionRecords: enabled);
    }
    throw const FormatException('Invalid privacy preferences response.');
  }
}
