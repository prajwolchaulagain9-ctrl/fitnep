import 'dart:async';

import 'package:fitnep/features/notifications/domain/entities/notification_entity.dart';
import 'package:fitnep/features/notifications/domain/repositories/notification_repository.dart';
import 'package:fitnep/features/notifications/presentation/controllers/notification_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an older mark-all completion cannot update the next account', () async {
    final pending = Completer<void>();
    final first = _FakeNotificationRepository([
      _notification(
        id: 'old-account',
        isRead: false,
        createdAt: DateTime.utc(2026),
      ),
    ], markAllCompleter: pending);
    final next = _FakeNotificationRepository([
      _notification(
        id: 'new-account',
        isRead: false,
        createdAt: DateTime.utc(2026),
      ),
    ]);
    final container = ProviderContainer(
      overrides: [notificationRepositoryProvider.overrideWithValue(first)],
    );
    addTearDown(container.dispose);
    await container.read(notificationControllerProvider.future);
    final request = container
        .read(notificationControllerProvider.notifier)
        .markAllAsRead();
    container.updateOverrides([
      notificationRepositoryProvider.overrideWithValue(next),
    ]);
    await container.read(notificationControllerProvider.future);
    pending.complete();
    await request;
    final notifications = container
        .read(notificationControllerProvider)
        .requireValue;
    expect(notifications.single.id, 'new-account');
    expect(notifications.single.isRead, isFalse);
    expect(next.markAllCalls, 0);
    expect(container.read(notificationMarkAllReadInProgressProvider), isFalse);
  });
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

  test('marks every unread notification read and refreshes the list', () async {
    final alreadyRead = _notification(
      id: 'already-read',
      isRead: true,
      createdAt: DateTime.utc(2026, 11, 18),
    );
    final repository = _FakeNotificationRepository([
      alreadyRead,
      _notification(
        id: 'unread-1',
        isRead: false,
        createdAt: DateTime.utc(2026, 11, 17),
      ),
      _notification(
        id: 'unread-2',
        isRead: false,
        createdAt: DateTime.utc(2026, 11, 16),
      ),
    ]);
    final container = ProviderContainer(
      overrides: [notificationRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(notificationControllerProvider.future);

    await container
        .read(notificationControllerProvider.notifier)
        .markAllAsRead();

    final notifications = container
        .read(notificationControllerProvider)
        .requireValue;
    expect(notifications.every((notification) => notification.isRead), isTrue);
    expect(container.read(unreadNotificationCountProvider), 0);
    expect(repository.markAllCalls, 1);
    expect(repository.fetchCalls, 2);
    expect(
      identical(
        notifications.firstWhere(
          (notification) => notification.id == 'already-read',
        ),
        alreadyRead,
      ),
      isTrue,
    );
  });

  test('prevents repeated mark-all requests while processing', () async {
    final markAllCompleter = Completer<void>();
    final repository = _FakeNotificationRepository([
      _notification(
        id: 'unread',
        isRead: false,
        createdAt: DateTime.utc(2026, 11, 18),
      ),
    ], markAllCompleter: markAllCompleter);
    final container = ProviderContainer(
      overrides: [notificationRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(notificationControllerProvider.future);
    final controller = container.read(notificationControllerProvider.notifier);

    final firstRequest = controller.markAllAsRead();
    final repeatedRequest = controller.markAllAsRead();

    expect(repository.markAllCalls, 1);
    expect(container.read(notificationMarkAllReadInProgressProvider), isTrue);

    markAllCompleter.complete();
    await Future.wait([firstRequest, repeatedRequest]);

    expect(container.read(notificationMarkAllReadInProgressProvider), isFalse);
    expect(container.read(unreadNotificationCountProvider), 0);
  });

  test('keeps unread state when mark-all fails', () async {
    final repository = _FakeNotificationRepository([
      _notification(
        id: 'unread',
        isRead: false,
        createdAt: DateTime.utc(2026, 11, 18),
      ),
    ], markAllError: Exception('Offline'));
    final container = ProviderContainer(
      overrides: [notificationRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(notificationControllerProvider.future);

    await expectLater(
      container.read(notificationControllerProvider.notifier).markAllAsRead(),
      throwsException,
    );

    expect(container.read(unreadNotificationCountProvider), 1);
    expect(container.read(notificationMarkAllReadInProgressProvider), isFalse);
    expect(repository.fetchCalls, 1);
  });

  test('read-all state persists when the controller is recreated', () async {
    final repository = _FakeNotificationRepository([
      _notification(
        id: 'unread',
        isRead: false,
        createdAt: DateTime.utc(2026, 11, 18),
      ),
    ]);
    final firstContainer = ProviderContainer(
      overrides: [notificationRepositoryProvider.overrideWithValue(repository)],
    );
    await firstContainer.read(notificationControllerProvider.future);
    await firstContainer
        .read(notificationControllerProvider.notifier)
        .markAllAsRead();
    firstContainer.dispose();

    final restartedContainer = ProviderContainer(
      overrides: [notificationRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(restartedContainer.dispose);
    await restartedContainer.read(notificationControllerProvider.future);

    expect(restartedContainer.read(unreadNotificationCountProvider), 0);
  });
}

class _FakeNotificationRepository implements NotificationRepository {
  List<NotificationEntity> notifications;
  final Completer<void>? markCompleter;
  final Object? markError;
  final Completer<void>? markAllCompleter;
  final Object? markAllError;
  final List<String> markedIds = [];
  int markAllCalls = 0;
  int fetchCalls = 0;

  _FakeNotificationRepository(
    List<NotificationEntity> notifications, {
    this.markCompleter,
    this.markError,
    this.markAllCompleter,
    this.markAllError,
  }) : notifications = List<NotificationEntity>.of(notifications);

  @override
  Future<List<NotificationEntity>> getNotifications() async {
    fetchCalls++;
    return List<NotificationEntity>.unmodifiable(notifications);
  }

  @override
  Future<void> markAsRead(String notificationId) {
    markedIds.add(notificationId);
    if (markError != null) return Future<void>.error(markError!);
    return markCompleter?.future ?? Future<void>.value();
  }

  @override
  Future<void> markAllAsRead() async {
    markAllCalls++;
    if (markAllError != null) throw markAllError!;
    if (markAllCompleter != null) await markAllCompleter!.future;
    notifications = notifications
        .map(
          (notification) => notification.isRead
              ? notification
              : notification.copyWith(isRead: true),
        )
        .toList(growable: false);
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
