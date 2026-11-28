import 'dart:async';

import 'package:fitnep/app/routes/app_routes.dart';
import 'package:fitnep/features/notifications/data/notification_entity.dart';
import 'package:fitnep/features/notifications/data/notification_repository.dart';
import 'package:fitnep/features/notifications/notification_controller.dart';
import 'package:fitnep/features/notifications/pages/notifications_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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

  final navigationCases = <(NotificationType, String, String)>[
    (NotificationType.dietPlan, 'plan-42', 'plan:plan-42'),
    (NotificationType.message, 'conversation-42', 'message:conversation-42'),
    (NotificationType.task, 'task-42', 'task:task-42'),
    (NotificationType.payment, 'payment-42', 'payment:payment-42'),
  ];

  for (final testCase in navigationCases) {
    testWidgets('opens the correct ${testCase.$1.name} destination', (
      tester,
    ) async {
      final repository = _FakeNotificationRepository([
        _notification(
          title: 'Open ${testCase.$1.name}',
          isRead: false,
          createdAt: DateTime.utc(2026, 11, 18, 9),
          type: testCase.$1,
          referenceId: testCase.$2,
        ),
      ]);
      final router = _buildTestRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open ${testCase.$1.name}'));
      await tester.pumpAndSettle();

      expect(find.text(testCase.$3), findsOneWidget);
      expect(repository.markedIds, ['Open ${testCase.$1.name}']);
    });
  }

  testWidgets(
    'handles an invalid reference without navigating or marking read',
    (tester) async {
      final repository = _FakeNotificationRepository([
        _notification(
          title: 'Invalid reference notification',
          isRead: false,
          createdAt: DateTime.utc(2026, 11, 18, 9),
          type: NotificationType.task,
          referenceId: '   ',
        ),
      ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(home: NotificationsPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Invalid reference notification'));
      await tester.pump();

      expect(
        find.text(
          'This notification has an invalid reference and cannot be opened.',
        ),
        findsOneWidget,
      );
      expect(repository.markedIds, isEmpty);
    },
  );

  testWidgets('marks all unread notifications and shows success feedback', (
    tester,
  ) async {
    final markAllCompleter = Completer<void>();
    final repository = _FakeNotificationRepository([
      _notification(
        title: 'Unread notification',
        isRead: false,
        createdAt: DateTime.utc(2026, 11, 18, 9),
      ),
      _notification(
        title: 'Already read notification',
        isRead: true,
        createdAt: DateTime.utc(2026, 11, 17, 9),
      ),
    ], markAllCompleter: markAllCompleter);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: NotificationsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mark All as Read'));
    await tester.pump();

    expect(find.text('Marking as read...'), findsOneWidget);
    expect(repository.markAllCalls, 1);
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Marking as read...'),
          )
          .onPressed,
      isNull,
    );

    markAllCompleter.complete();
    await tester.pumpAndSettle();

    expect(find.text('0 unread'), findsOneWidget);
    expect(find.text('Unread'), findsNothing);
    expect(find.text('Mark All as Read'), findsNothing);
    expect(find.text('All notifications marked as read.'), findsOneWidget);
  });

  testWidgets('hides mark-all when every notification is already read', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationRepositoryProvider.overrideWithValue(
            _FakeNotificationRepository([
              _notification(
                title: 'Read notification',
                isRead: true,
                createdAt: DateTime.utc(2026, 11, 18, 9),
              ),
            ]),
          ),
        ],
        child: const MaterialApp(home: NotificationsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('0 unread'), findsOneWidget);
    expect(find.text('Mark All as Read'), findsNothing);
  });

  testWidgets('keeps unread UI and allows retry after mark-all fails', (
    tester,
  ) async {
    final repository = _FakeNotificationRepository([
      _notification(
        title: 'Unread notification',
        isRead: false,
        createdAt: DateTime.utc(2026, 11, 18, 9),
      ),
    ], markAllError: Exception('Network unavailable'));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: NotificationsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mark All as Read'));
    await tester.pumpAndSettle();

    expect(find.text('1 unread'), findsOneWidget);
    expect(find.text('Unread'), findsOneWidget);
    expect(find.text('Mark All as Read'), findsOneWidget);
    expect(find.text('Exception: Network unavailable'), findsOneWidget);
    expect(repository.markAllCalls, 1);
  });
}

class _FakeNotificationRepository implements NotificationRepository {
  List<NotificationEntity> notifications;
  final Completer<void>? markAllCompleter;
  final Object? markAllError;
  final List<String> markedIds = [];
  int markAllCalls = 0;

  _FakeNotificationRepository(
    List<NotificationEntity> notifications, {
    this.markAllCompleter,
    this.markAllError,
  }) : notifications = List<NotificationEntity>.of(notifications);

  @override
  Future<List<NotificationEntity>> getNotifications() async => notifications;

  @override
  Future<void> markAsRead(String notificationId) async {
    markedIds.add(notificationId);
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

class _FutureNotificationRepository implements NotificationRepository {
  final Future<List<NotificationEntity>> notifications;

  _FutureNotificationRepository(this.notifications);

  @override
  Future<List<NotificationEntity>> getNotifications() => notifications;

  @override
  Future<void> markAsRead(String notificationId) async {}

  @override
  Future<void> markAllAsRead() async {}
}

NotificationEntity _notification({
  required String title,
  required bool isRead,
  required DateTime createdAt,
  NotificationType type = NotificationType.message,
  String? referenceId,
}) {
  return NotificationEntity(
    id: title,
    recipientId: 'user-1',
    title: title,
    message: 'Notification message',
    type: type,
    referenceId: referenceId,
    isRead: isRead,
    createdAt: createdAt,
  );
}

GoRouter _buildTestRouter() {
  Widget destination(String label, GoRouterState state) {
    return Scaffold(body: Text('$label:${state.pathParameters['id']}'));
  }

  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const NotificationsPage()),
      GoRoute(
        path: AppRoutes.dietPlanDetails,
        name: AppRoutes.dietPlanDetailsName,
        builder: (_, state) => destination('plan', state),
      ),
      GoRoute(
        path: AppRoutes.messageThread,
        name: AppRoutes.messageThreadName,
        builder: (_, state) => destination('message', state),
      ),
      GoRoute(
        path: AppRoutes.taskDetails,
        name: AppRoutes.taskDetailsName,
        builder: (_, state) => destination('task', state),
      ),
      GoRoute(
        path: AppRoutes.paymentDetails,
        name: AppRoutes.paymentDetailsName,
        builder: (_, state) => destination('payment', state),
      ),
    ],
  );
}
