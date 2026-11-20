class PackageEntity {
  final String id;
  final String name;
  final int durationMonths;
  final double price;
  final String featureDescription;
  final bool isActive;
  final DateTime createdAt;

  const PackageEntity({
    required this.id,
    required this.name,
    required this.durationMonths,
    required this.price,
    required this.featureDescription,
    required this.isActive,
    required this.createdAt,
  });

  PackageEntity copyWith({
    String? name,
    int? durationMonths,
    double? price,
    String? featureDescription,
    bool? isActive,
  }) {
    return PackageEntity(
      id: id,
      name: name ?? this.name,
      durationMonths: durationMonths ?? this.durationMonths,
      price: price ?? this.price,
      featureDescription: featureDescription ?? this.featureDescription,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
    );
  }
}
