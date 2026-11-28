import 'package:fitnep/features/notifications/data/notification_model.dart';
import 'package:fitnep/features/notifications/data/notification_entity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationModel', () {
    test('parses the backend notification contract', () {
      final model = NotificationModel.fromJson({
        'id': 'notification-1',
        'recipient_id': 'user-1',
        'title': 'Diet plan updated',
        'message': 'Your weekly plan is ready.',
        'type': 'diet_plan',
        'reference_id': 'plan-1',
        'is_read': false,
        'created_at': '2026-11-18T08:30:00Z',
      });

      expect(model.id, 'notification-1');
      expect(model.recipientId, 'user-1');
      expect(model.type, NotificationType.dietPlan);
      expect(model.referenceId, 'plan-1');
      expect(model.isRead, isFalse);
      expect(model.createdAt, DateTime.utc(2026, 11, 18, 8, 30));
    });

    test('supports numeric read flags and unknown notification types', () {
      final model = NotificationModel.fromJson({
        'id': 'notification-2',
        'recipient_id': 'user-1',
        'title': 'Account update',
        'message': 'Your account was updated.',
        'type': 'account',
        'reference_id': null,
        'is_read': 1,
        'created_at': '2026-11-17T08:30:00Z',
      });

      expect(model.type, NotificationType.other);
      expect(model.referenceId, isNull);
      expect(model.isRead, isTrue);
    });

    test('parses assignment notification for dietitians', () {
      final model = NotificationModel.fromJson({
        'id': 'notification-assign-1',
        'recipient_id': 'dietitian-1',
        'title': 'New client assigned',
        'message': 'Jane Doe has been assigned to you.',
        'type': 'assignment',
        'reference_id': 'client-123',
        'is_read': false,
        'created_at': '2026-11-23T12:00:00Z',
      });

      expect(model.id, 'notification-assign-1');
      expect(model.recipientId, 'dietitian-1');
      expect(model.type, NotificationType.assignment);
      expect(model.referenceId, 'client-123');
      expect(model.isRead, isFalse);
    });
  });
}
