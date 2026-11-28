import 'audit_log_entity.dart';

class AuditLogModel extends AuditLogEntity {
  const AuditLogModel({
    required super.id,
    required super.adminId,
    required super.adminName,
    required super.clientId,
    required super.clientName,
    required super.actionType,
    super.reason,
    super.details,
    required super.timestamp,
  });

  factory AuditLogModel.fromJson(Map<String, dynamic> json) {
    return AuditLogModel(
      id: json['id'] as String,
      adminId: json['adminId'] as String,
      adminName: json['adminName'] as String,
      clientId: json['clientId'] as String,
      clientName: json['clientName'] as String,
      actionType: AuditActionType.values.firstWhere(
        (t) => t.name == json['actionType'],
        orElse: () => AuditActionType.profileUpdated,
      ),
      reason: json['reason'] as String?,
      details: json['details'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'adminId': adminId,
    'adminName': adminName,
    'clientId': clientId,
    'clientName': clientName,
    'actionType': actionType.name,
    'reason': reason,
    'details': details,
    'timestamp': timestamp.toIso8601String(),
  };
}
