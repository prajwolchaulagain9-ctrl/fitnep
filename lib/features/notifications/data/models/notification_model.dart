import '../../domain/entities/notification_entity.dart';

class NotificationModel extends NotificationEntity {
  const NotificationModel({
    required super.id,
    required super.recipientId,
    required super.title,
    required super.message,
    required super.type,
    required super.referenceId,
    required super.isRead,
    required super.createdAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: _requiredString(json, 'id'),
      recipientId: _requiredString(json, 'recipient_id'),
      title: _requiredString(json, 'title'),
      message: _requiredString(json, 'message'),
      type: _parseType(json['type']),
      referenceId: _optionalString(json['reference_id']),
      isRead: _parseBool(json['is_read']),
      createdAt: _parseDate(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'recipient_id': recipientId,
    'title': title,
    'message': message,
    'type': switch (type) {
      NotificationType.dietPlan => 'diet_plan',
      NotificationType.message => 'message',
      NotificationType.task => 'task',
      NotificationType.payment => 'payment',
      NotificationType.other => 'other',
    },
    'reference_id': referenceId,
    'is_read': isRead,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null || value.toString().trim().isEmpty) {
      throw FormatException('Notification field "$key" is missing.');
    }
    return value.toString();
  }

  static String? _optionalString(Object? value) {
    if (value == null || value.toString().trim().isEmpty) return null;
    return value.toString();
  }

  static bool _parseBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.toLowerCase().trim();
      if (normalized == 'true' || normalized == '1') return true;
      if (normalized == 'false' || normalized == '0') return false;
    }
    throw const FormatException('Notification field "is_read" is invalid.');
  }

  static DateTime _parseDate(Object? value) {
    final parsed = value == null ? null : DateTime.tryParse(value.toString());
    if (parsed == null) {
      throw const FormatException(
        'Notification field "created_at" is invalid.',
      );
    }
    return parsed;
  }

  static NotificationType _parseType(Object? value) {
    final normalized = value?.toString().trim().toLowerCase().replaceAll(
      RegExp(r'[\s-]+'),
      '_',
    );

    return switch (normalized) {
      'diet_plan' ||
      'dietplan' ||
      'meal_plan' ||
      'mealplan' => NotificationType.dietPlan,
      'message' || 'messages' || 'chat' => NotificationType.message,
      'task' || 'tasks' => NotificationType.task,
      'payment' || 'payments' => NotificationType.payment,
      _ => NotificationType.other,
    };
  }
}
