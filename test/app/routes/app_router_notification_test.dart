import 'package:fitnep/app/routes/app_router.dart';
import 'package:fitnep/app/routes/app_routes.dart';
import 'package:fitnep/features/notifications/domain/entities/notification_destination_record.dart';
import 'package:fitnep/features/notifications/domain/entities/notification_entity.dart';
import 'package:fitnep/features/notifications/domain/repositories/notification_destination_repository.dart';
import 'package:fitnep/features/notifications/presentation/controllers/notification_destination_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cases = <(String, NotificationType, String)>[
    (
      AppRoutes.dietPlanDetailsName,
      NotificationType.dietPlan,
      'Diet Plan Details',
    ),
    (AppRoutes.messageThreadName, NotificationType.message, 'Messages'),
    (AppRoutes.taskDetailsName, NotificationType.task, 'Task Details'),
    (AppRoutes.paymentDetailsName, NotificationType.payment, 'Payment Details'),
  ];

  for (final testCase in cases) {
    testWidgets('registered ${testCase.$2.name} route passes the record ID', (
      tester,
    ) async {
      final repository = _FakeDestinationRepository();
      final container = ProviderContainer(
        overrides: [
          notificationDestinationRepositoryProvider.overrideWithValue(
            repository,
          ),
        ],
      );
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);
      router.goNamed(testCase.$1, pathParameters: const {'id': 'record-99'});

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(testCase.$3), findsOneWidget);
      expect(find.text('Reference: record-99'), findsOneWidget);
      expect(repository.lastType, testCase.$2);
      expect(repository.lastReferenceId, 'record-99');
    });
  }
}

class _FakeDestinationRepository implements NotificationDestinationRepository {
  NotificationType? lastType;
  String? lastReferenceId;

  @override
  Future<NotificationDestinationRecord> getRecord(
    NotificationType type,
    String referenceId,
  ) async {
    lastType = type;
    lastReferenceId = referenceId;
    return NotificationDestinationRecord(
      id: referenceId,
      title: 'Loaded record',
      description: null,
      fields: const [],
    );
  }
}
