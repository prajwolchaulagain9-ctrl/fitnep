enum NotificationType { dietPlan, message, task, payment, other }

class NotificationEntity {
  final String id;
  final String recipientId;
  final String title;
  final String message;
  final NotificationType type;
  final String? referenceId;
  final bool isRead;
  final DateTime createdAt;

  const NotificationEntity({
    required this.id,
    required this.recipientId,
    required this.title,
    required this.message,
    required this.type,
    required this.referenceId,
    required this.isRead,
    required this.createdAt,
  });
}
