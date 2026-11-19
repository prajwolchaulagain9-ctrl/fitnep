class AppConstants {
  AppConstants._();

  static const notificationsEndpoint = 'notifications';
  static const notificationsReadAllEndpoint = 'notifications/read-all';

  /// Customer-facing packages endpoint (active packages only).
  static const packagesEndpoint = 'packages';

  /// Admin packages endpoint (all packages including inactive).
  static const adminPackagesEndpoint = 'admin/packages';

  static const purchasesEndpoint = 'purchases';
  static const currentPurchaseEndpoint = 'purchases/current';

  static String notificationReadEndpoint(String notificationId) =>
      '$notificationsEndpoint/${Uri.encodeComponent(notificationId)}/read';

  static String dietPlanEndpoint(String planId) =>
      'diet-plans/${Uri.encodeComponent(planId)}';

  static String conversationEndpoint(String conversationId) =>
      'conversations/${Uri.encodeComponent(conversationId)}';

  static String taskEndpoint(String taskId) =>
      'tasks/${Uri.encodeComponent(taskId)}';

  static String paymentEndpoint(String paymentId) =>
      'payments/${Uri.encodeComponent(paymentId)}';

  /// Admin endpoint to edit a specific package.
  static String packageEndpoint(String packageId) =>
      'packages/${Uri.encodeComponent(packageId)}';

  /// Admin endpoint to activate/deactivate a specific package.
  static String packageActiveEndpoint(String packageId) =>
      'packages/${Uri.encodeComponent(packageId)}/active';
}
