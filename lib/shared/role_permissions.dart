enum FitNepRole { client, staff, dietitian, admin }

extension FitNepRoleLabel on FitNepRole {
  String get label => switch (this) {
    FitNepRole.client => 'Client',
    FitNepRole.staff => 'Staff',
    FitNepRole.dietitian => 'Dietitian',
    FitNepRole.admin => 'Admin/CEO',
  };
}

FitNepRole? parseRole(Object? value) => switch (value) {
  'client' => FitNepRole.client,
  'staff' => FitNepRole.staff,
  'dietitian' => FitNepRole.dietitian,
  'admin' => FitNepRole.admin,
  _ => null,
};

abstract final class FitNepPermissions {
  static const own = {
    'view_dashboard',
    'view_own_profile',
    'edit_own_profile',
    'view_own_notifications',
    'update_own_notifications',
    'view_own_workflow',
  };
  static const byRole = {
    FitNepRole.client: {
      ...own,
      'view_client_dashboard',
      'view_packages',
      'manage_own_membership',
      'manage_own_privacy',
      'view_client_records',
      'view_own_client_records',
      'collect_own_records',
      'view_own_diet_plans',
    },
    FitNepRole.staff: {
      ...own,
      'view_staff_dashboard',
      'view_assigned_clients',
      'view_client_records',
      'view_own_diet_plans',
    },
    FitNepRole.dietitian: {
      ...own,
      'view_dietitian_dashboard',
      'view_assigned_clients',
      'view_client_records',
      'view_meal_records',
      'view_assigned_client_records',
      'manage_diet_plans',
      'view_own_diet_plans',
    },
    FitNepRole.admin: {
      ...own,
      'view_admin_dashboard',
      'view_packages',
      'manage_staff_accounts',
      'manage_dietitian_accounts',
      'manage_client_accounts',
      'manage_user_roles',
      'manage_business_settings',
      'verify_payments',
      'view_audit_logs',
      'manage_client_assignments',
      'view_client_records',
      'view_own_diet_plans',
    },
  };
}

class AuthorizationService {
  const AuthorizationService(
    this.role, {
    this.auditRead = false,
    this.paymentsVerify = false,
  });
  final FitNepRole? role;
  final bool auditRead;
  final bool paymentsVerify;
  bool hasPermission(String permission) =>
      (FitNepPermissions.byRole[role]?.contains(permission) ?? false) ||
      (role == FitNepRole.staff &&
          ((auditRead && permission == 'view_audit_logs') ||
              (paymentsVerify && permission == 'verify_payments')));
}

String dashboardForRole(FitNepRole role) => switch (role) {
  FitNepRole.client => '/client/home',
  FitNepRole.staff => '/staff/home',
  FitNepRole.dietitian => '/dietitian/home',
  FitNepRole.admin => '/admin/home',
};
String? permissionForRoute(String path) {
  if (path == '/dashboard') return 'view_dashboard';
  if (path == '/client/home') return 'view_client_dashboard';
  if (path == '/staff/home') return 'view_staff_dashboard';
  if (path == '/dietitian/home') return 'view_dietitian_dashboard';
  if (path == '/admin/home') return 'view_admin_dashboard';
  if (path == '/account/profile') return 'view_own_profile';
  if (path == '/admin/users') return 'manage_user_roles';
  if (path.startsWith('/admin/staff-accounts')) return 'manage_staff_accounts';
  if (path == '/admin/audit-log') return 'view_audit_logs';
  if (path == '/admin/audit-log/legacy') return 'manage_user_roles';
  if (path == '/admin/package-approvals') return 'verify_payments';
  if (path.startsWith('/admin/clients')) return 'manage_client_accounts';
  if (path.startsWith('/admin/')) return 'manage_business_settings';
  if (path == '/care/clients') return 'view_assigned_clients';
  if (path.startsWith('/dietitian/assigned-clients/')) {
    return 'view_assigned_client_records';
  }
  if (path.startsWith('/care/clients/')) return 'view_assigned_client_records';
  if (path == '/client/records') return 'view_own_client_records';
  if (path == '/client/intake' || path.startsWith('/client/intake/')) {
    return 'view_own_client_records';
  }
  if (path == '/client/onboarding') return 'view_client_dashboard';
  if (path == '/client/packages' || path.startsWith('/client/checkout/')) {
    return 'manage_own_membership';
  }
  if (path == '/client/membership') return 'manage_own_membership';
  if (path == '/client/privacy-preferences') return 'manage_own_privacy';
  if (path.contains('notifications')) return 'view_own_notifications';
  if (path.startsWith('/diet-plans/') ||
      path.startsWith('/messages/') ||
      path.startsWith('/tasks/') ||
      path.startsWith('/payments/')) {
    return 'view_own_workflow';
  }
  return null;
}
