import '../../../../support/offline_hosted_session.dart';

import 'package:fitnep/app/routes/app_router.dart';
import 'package:fitnep/app/routes/app_routes.dart';
import 'package:fitnep/app/routes/route_access_gate.dart';
import 'package:fitnep/features/authentication/data/registration_privacy.dart';
import 'package:fitnep/features/dashboards/presentation/pages/client_home_page.dart';
import 'package:fitnep/features/health_assessment/domain/entities/client_intake.dart';
import 'package:fitnep/features/health_assessment/presentation/controllers/client_intake_controller.dart';
import 'package:fitnep/features/notifications/domain/entities/notification_entity.dart';
import 'package:fitnep/features/notifications/domain/repositories/notification_repository.dart';
import 'package:fitnep/features/notifications/presentation/controllers/notification_controller.dart';
import 'package:fitnep/features/notifications/presentation/pages/notifications_page.dart';
import 'package:fitnep/features/purchases/domain/entities/package_purchase_entity.dart';
import 'package:fitnep/features/purchases/domain/repositories/package_purchase_repository.dart';
import 'package:fitnep/features/purchases/presentation/controllers/membership_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('client home opens notifications and a pending intake request', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeNotificationRepository([
      NotificationEntity(
        id: 'intake-request',
        recipientId: 'authenticated-client',
        title: 'Intake information requested',
        message: 'Open the intake form to review the request.',
        type: NotificationType.intake,
        referenceId: 'authenticated-client',
        isRead: false,
        createdAt: DateTime.utc(2026, 11, 18),
      ),
      _notification('read', isRead: true, day: 17),
      _notification('older-unread', isRead: false, day: 16),
    ]);
    final container = ProviderContainer(
      overrides: [
        offlineHostedSessionOverride,
        registrationAcceptedProvider.overrideWith((ref, uid) async => true),
        routeSessionProvider.overrideWith(
          (ref) async => (
            uid: 'authenticated-client',
            role: FitNepRole.client,
            auditRead: false,
          ),
        ),
        notificationRepositoryProvider.overrideWithValue(repository),
        ownClientIntakeProvider('authenticated-client').overrideWith(
          (ref) async => const ClientIntake(
            clientId: 'authenticated-client',
            allergies: [],
            medicalConditions: [],
            sections: [],
            submittedAt: null,
            updatedAt: null,
            status: ClientIntakeStatus.informationRequested,
            reviewAction: ClientIntakeReviewAction.clarificationRequested,
            reviewNote: 'Synthetic clarification note',
          ),
        ),
        packagePurchaseRepositoryProvider.overrideWithValue(_EmptyPurchases()),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);
    router.goNamed(AppRoutes.clientHomeName);

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
    expect(find.text('Intake information requested'), findsOneWidget);
    expect(find.text('Synthetic clarification note'), findsNothing);

    await tester.tap(find.text('Mark All as Read'));
    await tester.pumpAndSettle();

    expect(repository.markAllCalls, 1);
    expect(find.text('0 unread'), findsOneWidget);

    await tester.tap(find.text('Intake information requested'));
    await tester.pumpAndSettle();
    expect(find.text('Your intake form'), findsOneWidget);
    expect(find.text('Pending Information'), findsOneWidget);
    expect(find.text('Synthetic clarification note'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(ClientHomePage), findsOneWidget);
    expect(find.byKey(ClientHomePage.notificationBadgeKey), findsNothing);
  });
}

class _EmptyPurchases extends Fake implements PackagePurchaseRepository {
  @override
  Future<PackagePurchaseEntity?> getCurrentPurchase() async => null;
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
