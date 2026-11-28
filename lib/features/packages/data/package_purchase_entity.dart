import 'package_models.dart';

class PackagePurchaseEntity {
  final String id;
  final String packageId;
  final String packageName;
  final double pricePaid;
  final int durationMonths;
  final String featureDescription;
  final DateTime? purchasedAt;
  final DateTime? expiresAt;
  final MembershipStatus status;
  final int? daysRemaining;
  final int? durationDays;

  const PackagePurchaseEntity({
    required this.id,
    required this.packageId,
    required this.packageName,
    required this.pricePaid,
    required this.durationMonths,
    required this.featureDescription,
    required this.purchasedAt,
    required this.expiresAt,
    this.status = MembershipStatus.active,
    this.daysRemaining,
    this.durationDays,
  });

  bool get isPending => status == MembershipStatus.pending;
  bool get isCurrent => status != MembershipStatus.expired && !isExpired;
  bool get isExpired =>
      expiresAt != null && !expiresAt!.isAfter(DateTime.now());
  String get statusLabel => isPending
      ? 'Pending'
      : status == MembershipStatus.scheduled
      ? 'Scheduled'
      : isExpired
      ? 'Expired'
      : 'Active';
}
