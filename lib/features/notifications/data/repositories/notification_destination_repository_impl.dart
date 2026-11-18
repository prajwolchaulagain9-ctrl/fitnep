import '../../domain/entities/notification_destination_record.dart';
import '../../domain/entities/notification_entity.dart';
import '../../domain/repositories/notification_destination_repository.dart';
import '../datasources/notification_destination_remote_datasource.dart';

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
