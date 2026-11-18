import 'package:fitnep/features/notifications/domain/entities/notification_entity.dart';
import 'package:fitnep/features/notifications/domain/repositories/notification_repository.dart';
import 'package:fitnep/features/notifications/presentation/controllers/notification_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'sorts notifications newest first and calculates unread count',
    () async {
      final repository = _FakeNotificationRepository([
        _notification(
          id: 'older',
          isRead: false,
          createdAt: DateTime.utc(2026, 11, 17),
        ),
        _notification(
          id: 'newest',
          isRead: true,
          createdAt: DateTime.utc(2026, 11, 18),
        ),
        _notification(
          id: 'oldest',
          isRead: false,
          createdAt: DateTime.utc(2026, 11, 16),
        ),
      ]);
      final container = ProviderContainer(
        overrides: [
          notificationRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      final notifications = await container.read(
        notificationControllerProvider.future,
      );

      expect(notifications.map((notification) => notification.id), [
        'newest',
        'older',
        'oldest',
      ]);
      expect(container.read(unreadNotificationCountProvider), 2);
    },
  );
}

class _FakeNotificationRepository implements NotificationRepository {
  final List<NotificationEntity> notifications;

  _FakeNotificationRepository(this.notifications);

  @override
  Future<List<NotificationEntity>> getNotifications() async => notifications;
}

NotificationEntity _notification({
  required String id,
  required bool isRead,
  required DateTime createdAt,
}) {
  return NotificationEntity(
    id: id,
    recipientId: 'user-1',
    title: id,
    message: 'Notification message',
    type: NotificationType.message,
    referenceId: null,
    isRead: isRead,
    createdAt: createdAt,
  );
}
