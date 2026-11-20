import '../../domain/entities/package_entity.dart';

class PackageModel extends PackageEntity {
  const PackageModel({
    required super.id,
    required super.name,
    required super.durationMonths,
    required super.price,
    required super.featureDescription,
    required super.isActive,
    required super.createdAt,
  });

  factory PackageModel.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final duration = json['duration_months'];
    final price = json['price'];
    final featureDescription = json['feature_description'];
    final isActiveRaw = json['is_active'];
    final createdAt = json['created_at'];
    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('Package id is invalid.');
    }
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException('Package name is invalid.');
    }
    if (duration is! num || duration <= 0 || duration % 1 != 0) {
      throw const FormatException('Package duration is invalid.');
    }
    if (price is! num || !price.isFinite || price <= 0) {
      throw const FormatException('Package price is invalid.');
    }
    if (featureDescription is! String || featureDescription.trim().isEmpty) {
      throw const FormatException('Package feature description is invalid.');
    }
    // is_active defaults to true for legacy records that pre-date the field.
    final isActive = isActiveRaw is bool ? isActiveRaw : true;
    final parsedCreatedAt = createdAt is String
        ? DateTime.tryParse(createdAt)
        : null;
    if (parsedCreatedAt == null) {
      throw const FormatException('Package creation date is invalid.');
    }

    return PackageModel(
      id: id,
      name: name,
      durationMonths: duration.toInt(),
      price: price.toDouble(),
      featureDescription: featureDescription,
      isActive: isActive,
      createdAt: parsedCreatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'duration_months': durationMonths,
      'price': price,
      'feature_description': featureDescription,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
