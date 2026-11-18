class AppRoutes {
  AppRoutes._();

  // Shared
  static const notifications = '/notifications';

  // Admin
  static const adminClients = '/admin/clients';
  static const clientProfile = '/admin/clients/:id';
  static const auditLog = '/admin/audit-log';
}
