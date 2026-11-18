import 'package:fitnep/app/routes/app_router.dart';
import 'package:fitnep/features/dashboards/presentation/pages/client_home_page.dart';
import 'package:fitnep/features/notifications/domain/entities/notification_entity.dart';
import 'package:fitnep/features/notifications/domain/repositories/notification_repository.dart';
import 'package:fitnep/features/notifications/presentation/controllers/notification_controller.dart';
import 'package:fitnep/features/notifications/presentation/pages/notifications_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'client home bell shows unread count and opens client notifications',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _FakeNotificationRepository([
        _notification('newest', isRead: false, day: 18),
        _notification('read', isRead: true, day: 17),
        _notification('older-unread', isRead: false, day: 16),
      ]);
      final container = ProviderContainer(
        overrides: [
          notificationRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('FitNEP'), findsOneWidget);
      expect(find.byKey(ClientHomePage.notificationButtonKey), findsOneWidget);
      expect(find.byKey(ClientHomePage.notificationBadgeKey), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(ClientHomePage.notificationButtonKey));
      await tester.pumpAndSettle();

      expect(find.byType(NotificationsPage), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Newest'), findsOneWidget);

      await tester.tap(find.text('Mark All as Read'));
      await tester.pumpAndSettle();

      expect(repository.markAllCalls, 1);
      expect(find.text('0 unread'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byType(ClientHomePage), findsOneWidget);
      expect(find.byKey(ClientHomePage.notificationBadgeKey), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

class _FakeNotificationRepository implements NotificationRepository {
  List<NotificationEntity> notifications;
  int markAllCalls = 0;

  _FakeNotificationRepository(List<NotificationEntity> notifications)
    : notifications = List<NotificationEntity>.of(notifications);

  @override
  Future<List<NotificationEntity>> getNotifications() async =>
      List<NotificationEntity>.unmodifiable(notifications);

  @override
  Future<void> markAsRead(String notificationId) async {
    notifications = notifications
        .map(
          (notification) => notification.id == notificationId
              ? notification.copyWith(isRead: true)
              : notification,
        )
        .toList(growable: false);
  }

  @override
  Future<void> markAllAsRead() async {
    markAllCalls++;
    notifications = notifications
        .map((notification) => notification.copyWith(isRead: true))
        .toList(growable: false);
  }
}

NotificationEntity _notification(
  String id, {
  required bool isRead,
  required int day,
}) {
  return NotificationEntity(
    id: id,
    recipientId: 'authenticated-client',
    title: id
        .split('-')
        .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' '),
    message: 'Notification message',
    type: NotificationType.message,
    referenceId: 'conversation-$id',
    isRead: isRead,
    createdAt: DateTime.utc(2026, 11, day),
  );
}
