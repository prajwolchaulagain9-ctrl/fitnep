import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/entities/privacy_preferences.dart';

class PrivacyPreferencesLocalDatasource {
  static const _storageKey = 'privacy_preferences_v1';

  final FlutterSecureStorage _storage;

  const PrivacyPreferencesLocalDatasource({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  Future<PrivacyPreferences> readPreferences() async {
    final storedValue = await _storage.read(key: _storageKey);
    if (storedValue == null) return PrivacyPreferences.defaults;

    try {
      final decoded = jsonDecode(storedValue);
      if (decoded is! Map<String, dynamic>) {
        return PrivacyPreferences.defaults;
      }

      return PrivacyPreferences(
        shareNutritionRecords: decoded['shareNutritionRecords'] == true,
      );
    } on FormatException {
      // Malformed saved data must never enable sharing by accident.
      return PrivacyPreferences.defaults;
    }
  }

  Future<void> writePreferences(PrivacyPreferences preferences) {
    final encoded = jsonEncode({
      'shareNutritionRecords': preferences.shareNutritionRecords,
    });
    return _storage.write(key: _storageKey, value: encoded);
  }
}
