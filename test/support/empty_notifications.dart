import 'package:fitnep/features/notifications/notification_controller.dart';
import 'package:fitnep/features/notifications/data/notification_entity.dart';

class EmptyNotifications extends NotificationController {
  @override
  Future<List<NotificationEntity>> build() async => const [];
}
