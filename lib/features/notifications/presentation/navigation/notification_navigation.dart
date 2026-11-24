import '../../../../app/routes/app_routes.dart';
import '../../domain/entities/notification_entity.dart';

class NotificationNavigationTarget {
  final String routeName;
  final String referenceId;

  const NotificationNavigationTarget({
    required this.routeName,
    required this.referenceId,
  });

  factory NotificationNavigationTarget.fromNotification(
    NotificationEntity notification,
  ) {
    final referenceId = notification.referenceId?.trim();
    if (referenceId == null || referenceId.isEmpty) {
      throw const NotificationNavigationException(
        'This notification has an invalid reference and cannot be opened.',
      );
    }

    final routeName = switch (notification.type) {
      NotificationType.dietPlan => AppRoutes.dietPlanDetailsName,
      NotificationType.message => AppRoutes.messageThreadName,
      NotificationType.task => AppRoutes.taskDetailsName,
      NotificationType.payment => AppRoutes.paymentDetailsName,
      NotificationType.assignment => AppRoutes.dietitianAssignedClientName,
      NotificationType.other => throw const NotificationNavigationException(
        'This notification type does not have a destination yet.',
      ),
    };

    return NotificationNavigationTarget(
      routeName: routeName,
      referenceId: referenceId,
    );
  }
}

class NotificationNavigationException implements Exception {
  final String message;

  const NotificationNavigationException(this.message);

  @override
  String toString() => message;
}
