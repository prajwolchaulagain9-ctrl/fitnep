import '../../../../core/network/api_client.dart';
import '../../domain/entities/privacy_preferences.dart';
import '../../domain/repositories/privacy_preferences_repository.dart';

class PrivacyPreferencesRepositoryImpl implements PrivacyPreferencesRepository {
  static const _endpoint = 'privacy/preferences';
  static const _fields = {
    PrivacySharingCategory.nutritionRecords: 'share_nutrition_records',
    PrivacySharingCategory.mealPhotos: 'share_meal_photos',
    PrivacySharingCategory.progressPhotos: 'share_progress_photos',
    PrivacySharingCategory.activityData: 'share_activity_data',
  };
  final ApiClient _apiClient;

  const PrivacyPreferencesRepositoryImpl(this._apiClient);

  @override
  Future<PrivacyPreferences> loadPreferences() async {
    _ensureConfigured();
    final response = await _apiClient.dio.get<Object?>(_endpoint);
    return _decodePreferences(response.data);
  }

  @override
  Future<PrivacyPreferences> setSharing(
    PrivacySharingCategory category,
    bool enabled,
  ) async {
    _ensureConfigured();
    final response = await _apiClient.dio.patch<Object?>(
      _endpoint,
      data: {_fields[category]!: enabled},
    );
    return _decodePreferences(response.data);
  }

  void _ensureConfigured() {
    if (_apiClient.dio.options.baseUrl.trim().isEmpty) {
      throw StateError('The privacy preferences service is not configured.');
    }
  }

  PrivacyPreferences _decodePreferences(Object? body) {
    if (body case {'data': {'preferences': final Map preferences}}) {
      bool shared(PrivacySharingCategory category) =>
          preferences[_fields[category]] == true;

      return PrivacyPreferences(
        shareNutritionRecords: shared(PrivacySharingCategory.nutritionRecords),
        shareMealPhotos: shared(PrivacySharingCategory.mealPhotos),
        shareProgressPhotos: shared(PrivacySharingCategory.progressPhotos),
        shareActivityData: shared(PrivacySharingCategory.activityData),
      );
    }
    throw const FormatException('Invalid privacy preferences response.');
  }
}
