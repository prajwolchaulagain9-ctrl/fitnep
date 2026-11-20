/// The client's choices for sharing sensitive fitness and nutrition data.
///
/// Sharing is disabled by default. A client must opt in to each data category.
class PrivacyPreferences {
  const PrivacyPreferences({
    this.shareMealPhotos = false,
    this.shareProgressPhotos = false,
    this.shareActivityData = false,
  });

  static const defaults = PrivacyPreferences();

  final bool shareMealPhotos;
  final bool shareProgressPhotos;
  final bool shareActivityData;

  PrivacyPreferences copyWith({
    bool? shareMealPhotos,
    bool? shareProgressPhotos,
    bool? shareActivityData,
  }) {
    return PrivacyPreferences(
      shareMealPhotos: shareMealPhotos ?? this.shareMealPhotos,
      shareProgressPhotos: shareProgressPhotos ?? this.shareProgressPhotos,
      shareActivityData: shareActivityData ?? this.shareActivityData,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PrivacyPreferences &&
            other.shareMealPhotos == shareMealPhotos &&
            other.shareProgressPhotos == shareProgressPhotos &&
            other.shareActivityData == shareActivityData;
  }

  @override
  int get hashCode =>
      Object.hash(shareMealPhotos, shareProgressPhotos, shareActivityData);
}
