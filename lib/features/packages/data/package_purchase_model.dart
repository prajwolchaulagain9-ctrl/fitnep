import 'package_purchase_entity.dart';
import 'package_models.dart';

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
    super.status,
    super.daysRemaining,
    super.durationDays,
  });

  factory PackagePurchaseModel.fromJson(Map<String, dynamic> json) {
    final price = json['price_paid'];
    final duration = json['duration_months'];
    if (price is! num || !price.isFinite || price <= 0) {
      throw const FormatException('Purchase price is invalid.');
    }
    if (duration is! num || duration <= 0 || duration % 1 != 0) {
      throw const FormatException('Purchase duration is invalid.');
    }
    final status = json['status'] == null
        ? MembershipStatus.active
        : MembershipStatus.values.byName(json['status'] as String);
    final start = json['purchased_at'] == null
        ? null
        : DateTime.parse(_requiredString(json, 'purchased_at'));
    final end = json['expires_at'] == null
        ? null
        : DateTime.parse(_requiredString(json, 'expires_at'));
    if (status == MembershipStatus.pending
        ? start != null || end != null
        : start == null || end == null || !end.isAfter(start)) {
      throw const FormatException('Membership dates do not match its status.');
    }
    return PackagePurchaseModel(
      id: _requiredString(json, 'id'),
      packageId: _requiredString(json, 'package_id'),
      packageName: _requiredString(json, 'package_name'),
      pricePaid: price.toDouble(),
      durationMonths: duration.toInt(),
      featureDescription: _requiredString(json, 'feature_description'),
      purchasedAt: start,
      expiresAt: end,
      status: status,
      daysRemaining: json['days_remaining'] as int?,
      durationDays: json['duration_days'] as int?,
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
