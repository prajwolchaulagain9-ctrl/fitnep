import '../../domain/entities/notification_destination_record.dart';
import '../../domain/entities/notification_entity.dart';

class NotificationDestinationRecordModel extends NotificationDestinationRecord {
  const NotificationDestinationRecordModel({
    required super.id,
    required super.title,
    required super.description,
    required super.fields,
  });

  factory NotificationDestinationRecordModel.fromJson(
    Map<String, dynamic> json, {
    required NotificationType type,
    required String referenceId,
  }) {
    final responseId = _firstString(json, const ['id', 'uuid']);
    if (responseId != null && responseId != referenceId) {
      throw const FormatException(
        'The related record does not match the requested reference.',
      );
    }

    final title =
        _firstString(json, _titleKeys(type)) ??
        '${_recordLabel(type)} $referenceId';
    final description = _firstString(json, _descriptionKeys(type));

    return NotificationDestinationRecordModel(
      id: responseId ?? referenceId,
      title: title,
      description: description,
      fields: List<NotificationDestinationField>.unmodifiable(
        _buildFields(json, type),
      ),
    );
  }

  static List<String> _titleKeys(NotificationType type) => switch (type) {
    NotificationType.dietPlan => const ['title', 'name', 'plan_name'],
    NotificationType.message => const [
      'title',
      'subject',
      'participant_name',
      'recipient_name',
    ],
    NotificationType.task => const ['title', 'name', 'task_name'],
    NotificationType.payment => const [
      'title',
      'description',
      'invoice_number',
    ],
    NotificationType.assignment => const ['name', 'title'],
    NotificationType.other => const ['title', 'name'],
  };

  static List<String> _descriptionKeys(NotificationType type) => switch (type) {
    NotificationType.dietPlan => const ['description', 'notes', 'summary'],
    NotificationType.message => const [
      'message',
      'body',
      'content',
      'last_message',
    ],
    NotificationType.task => const ['description', 'notes', 'instructions'],
    NotificationType.payment => const ['notes', 'description'],
    NotificationType.assignment => const ['email'],
    NotificationType.other => const ['description', 'message'],
  };

  static List<NotificationDestinationField> _buildFields(
    Map<String, dynamic> json,
    NotificationType type,
  ) {
    final fields = <NotificationDestinationField>[];

    void add(String label, List<String> keys) {
      final value = _firstString(json, keys);
      if (value != null) {
        fields.add(NotificationDestinationField(label: label, value: value));
      }
    }

    switch (type) {
      case NotificationType.dietPlan:
        add('Status', const ['status']);
        add('Dietitian', const ['dietitian_name', 'created_by_name']);
        add('Start date', const ['start_date', 'starts_at']);
        add('End date', const ['end_date', 'ends_at']);
        add('Calorie target', const ['calorie_target', 'daily_calories']);
      case NotificationType.message:
        add('From', const ['sender_name', 'participant_name']);
        add('Sent at', const ['sent_at', 'created_at']);
      case NotificationType.task:
        add('Status', const ['status']);
        add('Priority', const ['priority']);
        add('Due date', const ['due_date', 'due_at']);
        add('Assigned by', const ['assigned_by_name', 'created_by_name']);
      case NotificationType.payment:
        add('Status', const ['status']);
        final amount = _firstString(json, const ['amount', 'total']);
        final currency = _firstString(json, const ['currency']);
        if (amount != null) {
          fields.add(
            NotificationDestinationField(
              label: 'Amount',
              value: currency == null ? amount : '$currency $amount',
            ),
          );
        }
        add('Payment method', const ['payment_method', 'method']);
        add('Paid at', const ['paid_at', 'payment_date', 'created_at']);
      case NotificationType.assignment:
        add('Email', const ['email']);
        add('Assigned at', const ['assigned_at']);
        add('Status', const ['assignment_status']);
      case NotificationType.other:
        add('Status', const ['status']);
    }

    return fields;
  }

  static String? _firstString(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value == null || value is Map || value is Iterable) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  static String _recordLabel(NotificationType type) => switch (type) {
    NotificationType.dietPlan => 'Diet plan',
    NotificationType.message => 'Conversation',
    NotificationType.task => 'Task',
    NotificationType.payment => 'Payment',
    NotificationType.assignment => 'Assigned client',
    NotificationType.other => 'Record',
  };
}
