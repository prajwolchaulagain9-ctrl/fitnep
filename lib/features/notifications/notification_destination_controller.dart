import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/notification_destination_remote_datasource.dart';
import 'data/notification_destination_repository_impl.dart';
import 'data/notification_destination_record.dart';
import 'data/notification_destination_repository.dart';
import 'data/get_notification_destination_usecase.dart';
import 'notification_controller.dart';

final notificationDestinationRemoteDatasourceProvider =
    Provider<NotificationDestinationRemoteDatasource>((ref) {
      return NotificationDestinationRemoteDatasourceImpl(
        ref.watch(apiClientProvider),
      );
    });

final notificationDestinationRepositoryProvider =
    Provider<NotificationDestinationRepository>((ref) {
      return NotificationDestinationRepositoryImpl(
        ref.watch(notificationDestinationRemoteDatasourceProvider),
      );
    });

final notificationDestinationProvider = FutureProvider.autoDispose
    .family<NotificationDestinationRecord, NotificationDestinationRequest>((
      ref,
      request,
    ) {
      return GetNotificationDestinationUseCase(
        ref.watch(notificationDestinationRepositoryProvider),
      )(request);
    });
