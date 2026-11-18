import '../entities/notification_destination_record.dart';
import '../repositories/notification_destination_repository.dart';

class GetNotificationDestinationUseCase {
  final NotificationDestinationRepository _repository;

  const GetNotificationDestinationUseCase(this._repository);

  Future<NotificationDestinationRecord> call(
    NotificationDestinationRequest request,
  ) {
    return _repository.getRecord(request.type, request.referenceId);
  }
}
