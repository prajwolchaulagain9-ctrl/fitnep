class PackagePurchaseEntity {
  final String id;
  final String packageId;
  final String packageName;
  final double pricePaid;
  final int durationMonths;
  final String featureDescription;
  final DateTime purchasedAt;
  final DateTime expiresAt;

  const PackagePurchaseEntity({
    required this.id,
    required this.packageId,
    required this.packageName,
    required this.pricePaid,
    required this.durationMonths,
    required this.featureDescription,
    required this.purchasedAt,
    required this.expiresAt,
  });

  bool get isExpired => !expiresAt.isAfter(DateTime.now());
}
