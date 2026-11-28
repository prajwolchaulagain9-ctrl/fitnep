import 'notification_entity.dart';
import 'notification_repository.dart';

class GetNotificationsUseCase {
  final NotificationRepository _repository;

  const GetNotificationsUseCase(this._repository);

  Future<List<NotificationEntity>> call() => _repository.getNotifications();
}
