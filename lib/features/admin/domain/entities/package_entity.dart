class PackageEntity {
  final String id;
  final String name;
  final int durationMonths;
  final double price;
  final String featureDescription;
  final DateTime createdAt;

  const PackageEntity({
    required this.id,
    required this.name,
    required this.durationMonths,
    required this.price,
    required this.featureDescription,
    required this.createdAt,
  });
}
