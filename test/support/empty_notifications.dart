import 'package:fitnep/features/notifications/presentation/controllers/notification_controller.dart';
import 'package:fitnep/features/notifications/domain/entities/notification_entity.dart';

class EmptyNotifications extends NotificationController {
  @override
  Future<List<NotificationEntity>> build() async => const [];
}
