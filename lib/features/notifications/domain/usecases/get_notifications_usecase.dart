import '../entities/notification_entity.dart';
import '../repositories/notification_repository.dart';

class GetNotificationsUseCase {
  final NotificationRepository _repository;

  const GetNotificationsUseCase(this._repository);

  Future<List<NotificationEntity>> call() => _repository.getNotifications();
}
