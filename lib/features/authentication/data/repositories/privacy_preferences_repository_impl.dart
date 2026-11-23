import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/entities/privacy_preferences.dart';
import '../../domain/repositories/privacy_preferences_repository.dart';

class PrivacyPreferencesRepositoryImpl implements PrivacyPreferencesRepository {
  static const _fields = {
    PrivacySharingCategory.nutritionRecords: 'share_nutrition_records',
    PrivacySharingCategory.mealPhotos: 'share_meal_photos',
    PrivacySharingCategory.progressPhotos: 'share_progress_photos',
    PrivacySharingCategory.activityData: 'share_activity_data',
  };
  final FirebaseAuth _auth;
  final DocumentReference<Map<String, dynamic>> _document;

  const PrivacyPreferencesRepositoryImpl(this._auth, this._document);

  @override
  Future<PrivacyPreferences> loadPreferences() async {
    _requireAccount();
    final snapshot = await _document.get(
      const GetOptions(source: Source.server),
    );
    _requireAccount();
    return _decode(snapshot.data());
  }

  PrivacyPreferences _decode(Map<String, dynamic>? preferences) {
    bool shared(PrivacySharingCategory category) =>
        preferences?[_fields[category]] == true;

    return PrivacyPreferences(
      shareNutritionRecords: shared(PrivacySharingCategory.nutritionRecords),
      shareMealPhotos: shared(PrivacySharingCategory.mealPhotos),
      shareProgressPhotos: shared(PrivacySharingCategory.progressPhotos),
      shareActivityData: shared(PrivacySharingCategory.activityData),
    );
  }

  @override
  Future<PrivacyPreferences> setSharing(
    PrivacySharingCategory category,
    bool enabled,
  ) async {
    _requireAccount();
    final field = _fields[category]!;
    // A transaction requires a connection and confirms the update before the
    // UI shows a new sharing choice.
    final saved = await _document.firestore.runTransaction((transaction) async {
      _requireAccount();
      final snapshot = await transaction.get(_document);
      _requireAccount();
      transaction.set(_document, {
        field: enabled,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return _decode({...?snapshot.data(), field: enabled});
    });
    _requireAccount();
    return saved;
  }

  void _requireAccount() {
    if (_auth.currentUser?.uid != _document.id) {
      throw StateError('The signed-in account changed.');
    }
  }
}
