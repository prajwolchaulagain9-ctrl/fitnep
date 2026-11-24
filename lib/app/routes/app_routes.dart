abstract final class AppRoutes {
  static const welcome = 'welcome';
  static const about = 'about';
  static const login = 'login';
  static const signup = 'signup';
  static const changeStaffPassword = 'change-staff-password';
  static const changeStaffPasswordPath = '/change-staff-password';
  static const verifyEmail = 'verifyEmail';
  static const appUnderDevelopment = 'appUnderDevelopment';
  static const forgotPassword = 'forgotPassword';
  static const resetPassword = 'resetPassword';
  static const privacyPolicy = 'privacyPolicy';

  static const welcomePath = '/';
  static const aboutPath = '/about';
  static const loginPath = '/login';
  static const signupPath = '/signup';
  static const verifyEmailPath = '/verify-email';
  static const appUnderDevelopmentPath = '/app-under-development';
  static const forgotPasswordPath = '/forgot-password';
  static const resetPasswordPath = '/reset-password';
  static const privacyPolicyPath = '/privacy-policy';
  static const termsPath = '/terms-and-conditions';
  static const demoEntry = '/demo';
  static const dashboard = '/dashboard';
  static const staffHome = '/staff/home';
  static const dietitianHome = '/dietitian/home';
  static const adminHome = '/admin/home';
  static const ownProfile = '/account/profile';
  static const adminUsers = '/admin/users';
  static const adminStaffAccounts = '/admin/staff-accounts';
  static const adminStaffHistory = '/admin/staff-accounts/history';
  static const assignedClients = '/care/clients';
  static const clientRecords = '/client/records';
  static const assignedClientRecords = '/care/clients/:id/records';
  static const accessDenied = '/access-denied';

  // Shared
  static const notifications = '/notifications';
  static const dietPlanDetails = '/diet-plans/:id';
  static const messageThread = '/messages/:id';
  static const taskDetails = '/tasks/:id';
  static const paymentDetails = '/payments/:id';
  static const dietitianAssignedClient = '/dietitian/assigned-clients/:id';

  // Client
  static const clientHome = '/client/home';
  static const clientNotifications = '/client/notifications';
  static const clientPrivacyPreferences = '/client/privacy-preferences';
  static const clientPackages = '/client/packages';
  static const clientMembership = '/client/membership';

  static const dietPlanDetailsName = 'diet-plan-details';
  static const messageThreadName = 'message-thread';
  static const taskDetailsName = 'task-details';
  static const paymentDetailsName = 'payment-details';
  static const dietitianAssignedClientName = 'dietitian-assigned-client';
  static const clientHomeName = 'client-home';
  static const clientNotificationsName = 'client-notifications';
  static const clientPackagesName = 'client-packages';
  static const clientMembershipName = 'client-membership';

  // Admin
  static const adminClients = '/admin/clients';
  static const clientProfile = '/admin/clients/:id';
  static const auditLog = '/admin/audit-log';
  static const adminPackageApprovals = '/admin/package-approvals';
  static const adminPackages = '/admin/packages';
  static const adminCreatePackage = '/admin/packages/create';
  static const adminPackageHistory = '/admin/packages/history';

  /// Returns the path for editing a specific package.
  static String adminEditPackage(String packageId) =>
      '/admin/packages/$packageId/edit';
}
