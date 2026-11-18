class AppRoutes {
  AppRoutes._();

  // Shared
  static const notifications = '/notifications';
  static const dietPlanDetails = '/diet-plans/:id';
  static const messageThread = '/messages/:id';
  static const taskDetails = '/tasks/:id';
  static const paymentDetails = '/payments/:id';

  static const dietPlanDetailsName = 'diet-plan-details';
  static const messageThreadName = 'message-thread';
  static const taskDetailsName = 'task-details';
  static const paymentDetailsName = 'payment-details';

  // Admin
  static const adminClients = '/admin/clients';
  static const clientProfile = '/admin/clients/:id';
  static const auditLog = '/admin/audit-log';
}
