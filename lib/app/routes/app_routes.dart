abstract final class AppRoutes {
  static const welcome = 'welcome';
  static const about = 'about';
  static const forgotPassword = 'forgotPassword';
  static const resetPassword = 'resetPassword';

  static const welcomePath = '/';
  static const aboutPath = '/about';
  static const forgotPasswordPath = '/forgot-password';
  static const resetPasswordPath = '/reset-password';

  // Shared
  static const notifications = '/notifications';
  static const dietPlanDetails = '/diet-plans/:id';
  static const messageThread = '/messages/:id';
  static const taskDetails = '/tasks/:id';
  static const paymentDetails = '/payments/:id';

  // Client
  static const clientHome = '/client/home';
  static const clientNotifications = '/client/notifications';
  static const clientPackages = '/client/packages';
  static const clientMembership = '/client/membership';

  static const dietPlanDetailsName = 'diet-plan-details';
  static const messageThreadName = 'message-thread';
  static const taskDetailsName = 'task-details';
  static const paymentDetailsName = 'payment-details';
  static const clientHomeName = 'client-home';
  static const clientNotificationsName = 'client-notifications';
  static const clientPackagesName = 'client-packages';
  static const clientMembershipName = 'client-membership';

  // Admin
  static const adminClients = '/admin/clients';
  static const clientProfile = '/admin/clients/:id';
  static const auditLog = '/admin/audit-log';
  static const adminPackages = '/admin/packages';
  static const adminCreatePackage = '/admin/packages/create';

  /// Returns the path for editing a specific package.
  static String adminEditPackage(String packageId) =>
      '/admin/packages/$packageId/edit';
}
