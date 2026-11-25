enum PrivacySharingCategory {
  nutritionRecords,
  mealPhotos,
  progressPhotos,
  activityData,
}

/// The client's choices for sharing records with their current assigned team.
///
/// Sharing is disabled by default and can be enabled only by the client.
class PrivacyPreferences {
  const PrivacyPreferences({
    this.shareNutritionRecords = false,
    this.shareMealPhotos = false,
    this.shareProgressPhotos = false,
    this.shareActivityData = false,
  });

  static const defaults = PrivacyPreferences();

  final bool shareNutritionRecords;
  final bool shareMealPhotos;
  final bool shareProgressPhotos;
  final bool shareActivityData;

  bool isShared(PrivacySharingCategory category) => switch (category) {
    PrivacySharingCategory.nutritionRecords => shareNutritionRecords,
    PrivacySharingCategory.mealPhotos => shareMealPhotos,
    PrivacySharingCategory.progressPhotos => shareProgressPhotos,
    PrivacySharingCategory.activityData => shareActivityData,
  };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PrivacyPreferences &&
            other.shareNutritionRecords == shareNutritionRecords &&
            other.shareMealPhotos == shareMealPhotos &&
            other.shareProgressPhotos == shareProgressPhotos &&
            other.shareActivityData == shareActivityData;
  }

  @override
  int get hashCode => Object.hash(
    shareNutritionRecords,
    shareMealPhotos,
    shareProgressPhotos,
    shareActivityData,
  );
}
