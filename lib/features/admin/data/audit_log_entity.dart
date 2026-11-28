enum AuditActionType {
  clientDeactivated,
  clientReactivated,
  packageChanged,
  profileUpdated,
  paymentRecorded,
  authorizationDenied,
  userRoleChanged,
  accountStatusChanged,
  clientAssignmentChanged,
}

extension AuditActionTypeExtension on AuditActionType {
  String get displayName {
    switch (this) {
      case AuditActionType.clientDeactivated:
        return 'Client Deactivated';
      case AuditActionType.authorizationDenied:
        return 'Authorization denied';
      case AuditActionType.userRoleChanged:
        return 'User role changed';
      case AuditActionType.accountStatusChanged:
        return 'Account status changed';
      case AuditActionType.clientAssignmentChanged:
        return 'Client assignment changed';
      case AuditActionType.clientReactivated:
        return 'Client Reactivated';
      case AuditActionType.packageChanged:
        return 'Package Changed';
      case AuditActionType.profileUpdated:
        return 'Profile Updated';
      case AuditActionType.paymentRecorded:
        return 'Payment Recorded';
    }
  }

  String get icon {
    switch (this) {
      case AuditActionType.authorizationDenied:
        return '🔒';
      case AuditActionType.userRoleChanged:
        return '👤';
      case AuditActionType.accountStatusChanged:
        return '✅';
      case AuditActionType.clientAssignmentChanged:
        return '👥';
      case AuditActionType.clientDeactivated:
        return '🚫';
      case AuditActionType.clientReactivated:
        return '✅';
      case AuditActionType.packageChanged:
        return '📦';
      case AuditActionType.profileUpdated:
        return '✏️';
      case AuditActionType.paymentRecorded:
        return '💳';
    }
  }
}

class AuditLogEntity {
  final String id;
  final String adminId;
  final String adminName;
  final String clientId;
  final String clientName;
  final AuditActionType actionType;
  final String? reason;
  final String? details;
  final DateTime timestamp;

  const AuditLogEntity({
    required this.id,
    required this.adminId,
    required this.adminName,
    required this.clientId,
    required this.clientName,
    required this.actionType,
    this.reason,
    this.details,
    required this.timestamp,
  });
}
