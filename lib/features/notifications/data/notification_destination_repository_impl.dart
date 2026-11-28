import 'notification_destination_record.dart';
import 'notification_entity.dart';
import 'notification_destination_repository.dart';
import 'notification_destination_remote_datasource.dart';

class NotificationDestinationRepositoryImpl
    implements NotificationDestinationRepository {
  final NotificationDestinationRemoteDatasource _remoteDatasource;

  const NotificationDestinationRepositoryImpl(this._remoteDatasource);

  @override
  Future<NotificationDestinationRecord> getRecord(
    NotificationType type,
    String referenceId,
  ) {
    return _remoteDatasource.getRecord(type, referenceId);
  }
}
