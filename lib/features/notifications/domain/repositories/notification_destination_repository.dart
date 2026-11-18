import '../entities/notification_destination_record.dart';
import '../entities/notification_entity.dart';

abstract class NotificationDestinationRepository {
  Future<NotificationDestinationRecord> getRecord(
    NotificationType type,
    String referenceId,
  );
}
