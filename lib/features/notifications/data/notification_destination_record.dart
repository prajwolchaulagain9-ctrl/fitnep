import 'notification_entity.dart';

class NotificationDestinationRequest {
  final NotificationType type;
  final String referenceId;

  const NotificationDestinationRequest({
    required this.type,
    required this.referenceId,
  });

  @override
  bool operator ==(Object other) {
    return other is NotificationDestinationRequest &&
        other.type == type &&
        other.referenceId == referenceId;
  }

  @override
  int get hashCode => Object.hash(type, referenceId);
}

class NotificationDestinationRecord {
  final String id;
  final String title;
  final String? description;
  final List<NotificationDestinationField> fields;

  const NotificationDestinationRecord({
    required this.id,
    required this.title,
    required this.description,
    required this.fields,
  });
}

class NotificationDestinationField {
  final String label;
  final String value;

  const NotificationDestinationField({
    required this.label,
    required this.value,
  });
}
