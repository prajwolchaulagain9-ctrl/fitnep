/// The client's choice for sharing nutrition records with a dietitian.
///
/// Sharing is disabled by default and can be enabled only by the client.
class PrivacyPreferences {
  const PrivacyPreferences({this.shareNutritionRecords = false});

  static const defaults = PrivacyPreferences();

  final bool shareNutritionRecords;

  PrivacyPreferences copyWith({bool? shareNutritionRecords}) {
    return PrivacyPreferences(
      shareNutritionRecords:
          shareNutritionRecords ?? this.shareNutritionRecords,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PrivacyPreferences &&
            other.shareNutritionRecords == shareNutritionRecords;
  }

  @override
  int get hashCode => shareNutritionRecords.hashCode;
}
