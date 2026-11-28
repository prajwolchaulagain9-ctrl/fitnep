import 'notification_entity.dart';
import 'notification_repository.dart';
import 'notification_remote_datasource.dart';

class NotificationRepositoryImpl implements NotificationRepository {
  final NotificationRemoteDatasource _remoteDatasource;

  const NotificationRepositoryImpl(this._remoteDatasource);

  @override
  Future<List<NotificationEntity>> getNotifications() async {
    final notifications = await _remoteDatasource.getNotifications();
    notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List<NotificationEntity>.unmodifiable(notifications);
  }

  @override
  Future<void> markAsRead(String notificationId) =>
      _remoteDatasource.markAsRead(notificationId);

  @override
  Future<void> markAllAsRead() => _remoteDatasource.markAllAsRead();
}
