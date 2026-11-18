import 'package:fitnep/features/notifications/data/datasources/notification_destination_remote_datasource.dart';
import 'package:fitnep/features/notifications/domain/entities/notification_destination_record.dart';
import 'package:fitnep/features/notifications/domain/entities/notification_entity.dart';
import 'package:fitnep/features/notifications/domain/repositories/notification_destination_repository.dart';
import 'package:fitnep/features/notifications/presentation/controllers/notification_destination_controller.dart';
import 'package:fitnep/features/notifications/presentation/pages/notification_destination_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('loads and displays the referenced record', (tester) async {
    final repository = _FakeDestinationRepository(
      const NotificationDestinationRecord(
        id: 'task-17',
        title: 'Record weekly weight',
        description: 'Add the latest measurement before Friday.',
        fields: [
          NotificationDestinationField(label: 'Status', value: 'Pending'),
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationDestinationRepositoryProvider.overrideWithValue(
            repository,
          ),
        ],
        child: const MaterialApp(
          home: NotificationDestinationPage(
            type: NotificationType.task,
            referenceId: 'task-17',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Task Details'), findsOneWidget);
    expect(find.text('Record weekly weight'), findsOneWidget);
    expect(find.text('Reference: task-17'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(repository.lastType, NotificationType.task);
    expect(repository.lastReferenceId, 'task-17');
  });

  final errors = <(NotificationDestinationFailure, String, String)>[
    (
      NotificationDestinationFailure.notFound,
      'This task is no longer available. It may have been deleted.',
      'Record not found',
    ),
    (
      NotificationDestinationFailure.forbidden,
      'You do not have permission to view this task.',
      'Access denied',
    ),
    (
      NotificationDestinationFailure.network,
      'Could not load this task. Check your connection and try again.',
      'Could not load details',
    ),
  ];

  for (final testCase in errors) {
    testWidgets('shows ${testCase.$1.name} errors without crashing', (
      tester,
    ) async {
      final repository = _FakeDestinationRepository.error(
        NotificationDestinationException(testCase.$1, testCase.$2),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationDestinationRepositoryProvider.overrideWithValue(
              repository,
            ),
          ],
          child: const MaterialApp(
            home: NotificationDestinationPage(
              type: NotificationType.task,
              referenceId: 'task-17',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(testCase.$3), findsOneWidget);
      expect(find.text(testCase.$2), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

class _FakeDestinationRepository implements NotificationDestinationRepository {
  final NotificationDestinationRecord? record;
  final Object? error;
  NotificationType? lastType;
  String? lastReferenceId;

  _FakeDestinationRepository(this.record) : error = null;

  _FakeDestinationRepository.error(this.error) : record = null;

  @override
  Future<NotificationDestinationRecord> getRecord(
    NotificationType type,
    String referenceId,
  ) async {
    lastType = type;
    lastReferenceId = referenceId;
    if (error != null) throw error!;
    return record!;
  }
}
