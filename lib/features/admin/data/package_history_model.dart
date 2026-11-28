import 'package_history_entity.dart';

class PackageHistoryModel extends PackageHistoryEntity {
  const PackageHistoryModel({
    required super.id,
    required super.packageId,
    required super.packageName,
    required super.adminId,
    required super.adminName,
    required super.action,
    required super.previousValues,
    required super.newValues,
    required super.changedAt,
  });

  factory PackageHistoryModel.fromJson(Map<String, dynamic> json) {
    final changedAt = json['changed_at'];
    final parsedChangedAt = changedAt is String
        ? DateTime.tryParse(changedAt)
        : null;
    if (parsedChangedAt == null) {
      throw const FormatException('Package history date is invalid.');
    }
    return PackageHistoryModel(
      id: _requiredString(json, 'id'),
      packageId: _requiredString(json, 'package_id'),
      packageName: _requiredString(json, 'package_name'),
      adminId: _requiredString(json, 'admin_id'),
      adminName: _requiredString(json, 'admin_name'),
      action: _parseAction(json['action']),
      previousValues: json['previous_values'] == null
          ? null
          : _values(json['previous_values'], 'previous_values'),
      newValues: _values(json['new_values'], 'new_values'),
      changedAt: parsedChangedAt,
    );
  }

  static PackageHistoryAction _parseAction(Object? value) {
    if (value is! String) {
      throw const FormatException('Package history action is invalid.');
    }
    return PackageHistoryAction.values.firstWhere(
      (action) => action.name == value,
      orElse: () =>
          throw const FormatException('Package history action is invalid.'),
    );
  }

  static Map<String, Object?> _values(Object? value, String field) {
    if (value is! Map) {
      throw FormatException('Package history $field is invalid.');
    }
    return Map<String, Object?>.unmodifiable(Map<String, Object?>.from(value));
  }

  static String _requiredString(Map<String, dynamic> json, String field) {
    final value = json[field];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Package history $field is invalid.');
    }
    return value;
  }
}
