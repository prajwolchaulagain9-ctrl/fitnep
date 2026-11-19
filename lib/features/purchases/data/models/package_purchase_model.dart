import '../../domain/entities/package_purchase_entity.dart';

class PackagePurchaseModel extends PackagePurchaseEntity {
  const PackagePurchaseModel({
    required super.id,
    required super.packageId,
    required super.packageName,
    required super.pricePaid,
    required super.durationMonths,
    required super.featureDescription,
    required super.purchasedAt,
    required super.expiresAt,
  });

  factory PackagePurchaseModel.fromJson(Map<String, dynamic> json) {
    final price = json['price_paid'];
    final duration = json['duration_months'];
    if (price is! num || price <= 0) {
      throw const FormatException('Purchase price is invalid.');
    }
    if (duration is! num || duration <= 0 || duration % 1 != 0) {
      throw const FormatException('Purchase duration is invalid.');
    }
    return PackagePurchaseModel(
      id: _requiredString(json, 'id'),
      packageId: _requiredString(json, 'package_id'),
      packageName: _requiredString(json, 'package_name'),
      pricePaid: price.toDouble(),
      durationMonths: duration.toInt(),
      featureDescription: _requiredString(json, 'feature_description'),
      purchasedAt: DateTime.parse(_requiredString(json, 'purchased_at')),
      expiresAt: DateTime.parse(_requiredString(json, 'expires_at')),
    );
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Purchase $key is invalid.');
    }
    return value;
  }
}
