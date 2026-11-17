class PackageEntity {
  final String id;
  final String name;
  final String description;
  final int durationMonths;
  final double price;
  final List<String> features;

  const PackageEntity({
    required this.id,
    required this.name,
    required this.description,
    required this.durationMonths,
    required this.price,
    required this.features,
  });
}
