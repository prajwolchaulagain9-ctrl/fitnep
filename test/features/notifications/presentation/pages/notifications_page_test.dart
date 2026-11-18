import 'dart:async';

import 'package:fitnep/features/notifications/domain/entities/notification_entity.dart';
import 'package:fitnep/features/notifications/domain/repositories/notification_repository.dart';
import 'package:fitnep/features/notifications/presentation/controllers/notification_controller.dart';
import 'package:fitnep/features/notifications/presentation/pages/notifications_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'shows newest notifications first with an accurate unread count',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationRepositoryProvider.overrideWithValue(
              _FakeNotificationRepository([
                _notification(
                  title: 'Older notification',
                  isRead: false,
                  createdAt: DateTime.utc(2026, 11, 17, 9),
                ),
                _notification(
                  title: 'Newest notification',
                  isRead: true,
                  createdAt: DateTime.utc(2026, 11, 18, 9),
                ),
                _notification(
                  title: 'Unread notification',
                  isRead: false,
                  createdAt: DateTime.utc(2026, 11, 16, 9),
                ),
              ]),
            ),
          ],
          child: const MaterialApp(home: NotificationsPage()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('2 unread'), findsOneWidget);
      expect(find.text('Unread'), findsNWidgets(2));
      expect(
        tester.getTopLeft(find.text('Newest notification')).dy,
        lessThan(tester.getTopLeft(find.text('Older notification')).dy),
      );
    },
  );

  testWidgets('shows the empty state when the API returns no notifications', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationRepositoryProvider.overrideWithValue(
            _FakeNotificationRepository(const []),
          ),
        ],
        child: const MaterialApp(home: NotificationsPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('0 unread'), findsOneWidget);
    expect(find.text('No notifications yet'), findsOneWidget);
  });

  testWidgets('fits notification content on a compact mobile screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationRepositoryProvider.overrideWithValue(
            _FakeNotificationRepository([
              NotificationEntity(
                id: 'compact-screen',
                recipientId: 'user-1',
                title: 'Your weekly nutrition plan has been updated',
                message: 'Review the latest meal guidance prepared by your dietitian.',
                type: NotificationType.dietPlan,
                referenceId: 'plan-1',
                isRead: false,
                createdAt: DateTime.utc(2026, 11, 18, 9),
              ),
            ]),
          ),
        ],
        child: const MaterialApp(home: NotificationsPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('1 unread'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows loading and error states', (tester) async {
    final pendingNotifications = Completer<List<NotificationEntity>>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationRepositoryProvider.overrideWithValue(
            _FutureNotificationRepository(pendingNotifications.future),
          ),
        ],
        child: const MaterialApp(home: NotificationsPage()),
      ),
    );
    await tester.pump();

    expect(find.text('Loading notifications...'), findsOneWidget);

    pendingNotifications.completeError(Exception('Server unavailable'));
    await tester.pumpAndSettle();

    expect(find.text('Could not load notifications'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}

class _FakeNotificationRepository implements NotificationRepository {
  final List<NotificationEntity> notifications;

  _FakeNotificationRepository(this.notifications);

  @override
  Future<List<NotificationEntity>> getNotifications() async => notifications;
}

class _FutureNotificationRepository implements NotificationRepository {
  final Future<List<NotificationEntity>> notifications;

  _FutureNotificationRepository(this.notifications);

  @override
  Future<List<NotificationEntity>> getNotifications() => notifications;
}

NotificationEntity _notification({
  required String title,
  required bool isRead,
  required DateTime createdAt,
}) {
  return NotificationEntity(
    id: title,
    recipientId: 'user-1',
    title: title,
    message: 'Notification message',
    type: NotificationType.message,
    referenceId: null,
    isRead: isRead,
    createdAt: createdAt,
  );
}
