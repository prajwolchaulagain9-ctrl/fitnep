import 'dart:async';

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

  test(
    'marks a notification read optimistically and updates the count',
    () async {
      final markCompleter = Completer<void>();
      final repository = _FakeNotificationRepository([
        _notification(
          id: 'unread',
          isRead: false,
          createdAt: DateTime.utc(2026, 11, 18),
        ),
      ], markCompleter: markCompleter);
      final container = ProviderContainer(
        overrides: [
          notificationRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      await container.read(notificationControllerProvider.future);

      final markFuture = container
          .read(notificationControllerProvider.notifier)
          .markAsRead('unread');

      expect(container.read(unreadNotificationCountProvider), 0);
      expect(repository.markedIds, ['unread']);

      markCompleter.complete();
      await markFuture;
    },
  );

  test('restores unread state when the read API fails', () async {
    final repository = _FakeNotificationRepository([
      _notification(
        id: 'unread',
        isRead: false,
        createdAt: DateTime.utc(2026, 11, 18),
      ),
    ], markError: Exception('Offline'));
    final container = ProviderContainer(
      overrides: [notificationRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(notificationControllerProvider.future);

    await expectLater(
      container
          .read(notificationControllerProvider.notifier)
          .markAsRead('unread'),
      throwsException,
    );

    expect(container.read(unreadNotificationCountProvider), 1);
  });
}

class _FakeNotificationRepository implements NotificationRepository {
  final List<NotificationEntity> notifications;
  final Completer<void>? markCompleter;
  final Object? markError;
  final List<String> markedIds = [];

  _FakeNotificationRepository(
    this.notifications, {
    this.markCompleter,
    this.markError,
  });

  @override
  Future<List<NotificationEntity>> getNotifications() async => notifications;

  @override
  Future<void> markAsRead(String notificationId) {
    markedIds.add(notificationId);
    if (markError != null) return Future<void>.error(markError!);
    return markCompleter?.future ?? Future<void>.value();
  }
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
