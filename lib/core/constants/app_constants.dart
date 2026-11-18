class AppConstants {
  AppConstants._();

  static const notificationsEndpoint = 'notifications';
  static const notificationsReadAllEndpoint = 'notifications/read-all';

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
}
