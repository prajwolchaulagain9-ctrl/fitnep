class PackageOption {
  const PackageOption({
    required this.id,
    required this.name,
    required this.durationDays,
    required this.priceNpr,
    required this.features,
    this.durationMonths,
  });
  final String id;
  final String name;
  final int durationDays;
  final num priceNpr;
  final List<String> features;
  final int? durationMonths;

  String get durationLabel => durationMonths == null
      ? '$durationDays days'
      : '$durationMonths ${durationMonths == 1 ? 'month' : 'months'}';

  factory PackageOption.fromJson(Map<String, dynamic> json) {
    final item = PackageOption(
      id: json['id'] as String,
      name: json['name'] as String,
      durationDays:
          (json['duration_days'] ?? (json['duration_months'] as int) * 30)
              as int,
      durationMonths: json['duration_months'] as int?,
      priceNpr: (json['price_npr'] ?? json['price']) as num,
      features: json['features'] == null
          ? [json['feature_description'] as String]
          : List<String>.unmodifiable(json['features'] as List),
    );
    if (item.id.isEmpty ||
        item.name.isEmpty ||
        item.durationDays < 1 ||
        !item.priceNpr.isFinite ||
        item.priceNpr <= 0 ||
        item.features.isEmpty) {
      throw const FormatException('Invalid package record.');
    }
    return item;
  }
}

enum MembershipStatus { pending, active, scheduled, expired }

class PackageMembership {
  const PackageMembership({
    required this.id,
    required this.package,
    required this.status,
    required this.daysRemaining,
    this.startAt,
    this.endAt,
    this.clientId = '',
  });
  final String id;
  final PackageOption package;
  final MembershipStatus status;
  final int daysRemaining;
  final DateTime? startAt;
  final DateTime? endAt;
  final String clientId;

  factory PackageMembership.fromJson(Map<String, dynamic> json) {
    final status = MembershipStatus.values.byName(json['status'] as String);
    final start = json['start_at'] == null
        ? null
        : DateTime.parse(json['start_at'] as String);
    final end = json['end_at'] == null
        ? null
        : DateTime.parse(json['end_at'] as String);
    final remaining = json['days_remaining'] as int;
    if (remaining < 0 ||
        (status != MembershipStatus.pending &&
            (start == null || end == null || !end.isAfter(start)))) {
      throw const FormatException('Invalid membership dates.');
    }
    return PackageMembership(
      id: json['id'] as String,
      package: PackageOption.fromJson(
        Map<String, dynamic>.from(json['package'] as Map),
      ),
      status: status,
      daysRemaining: remaining,
      startAt: start,
      endAt: end,
      clientId: json['client_id'] as String? ?? '',
    );
  }
}
