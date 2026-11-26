import '../../../core/authorization/role_permissions.dart';

class FitNepAccount {
  const FitNepAccount({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.roleRevision = 0,
    this.auditRead = false,
  });
  final String id, fullName, email;
  final FitNepRole role;
  final bool isActive;
  final DateTime createdAt, updatedAt;
  final int roleRevision;
  final bool auditRead;
  factory FitNepAccount.fromJson(Map<String, dynamic> data) {
    final role = parseRole(data['role']);
    if (role == null ||
        !['active', 'inactive'].contains(data['account_status'])) {
      throw const FormatException(
        'This account has no valid FitNEP role or status.',
      );
    }
    return FitNepAccount(
      id: data['id'] as String,
      fullName: data['full_name'] as String? ?? '',
      email: data['email'] as String? ?? '',
      role: role,
      isActive: data['account_status'] == 'active',
      createdAt: DateTime.parse(data['created_at'] as String),
      updatedAt: DateTime.parse(data['updated_at'] as String),
      roleRevision: (data['role_revision'] as num?)?.toInt() ?? 0,
      auditRead: role == FitNepRole.staff && data['audit_read'] == true,
    );
  }
}

class AuthorizationFailure implements Exception {
  const AuthorizationFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
