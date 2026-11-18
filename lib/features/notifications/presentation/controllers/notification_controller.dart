import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/storage/token_storage.dart';
import '../../data/datasources/notification_remote_datasource.dart';
import '../../data/repositories/notification_repository_impl.dart';
import '../../domain/entities/notification_entity.dart';
import '../../domain/repositories/notification_repository.dart';
import '../../domain/usecases/get_notifications_usecase.dart';
import '../../domain/usecases/mark_all_notifications_as_read_usecase.dart';
import '../../domain/usecases/mark_notification_as_read_usecase.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return const TokenStorage();
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(tokenStorage: ref.watch(tokenStorageProvider));
});

final notificationRemoteDatasourceProvider =
    Provider<NotificationRemoteDatasource>((ref) {
      return NotificationRemoteDatasourceImpl(ref.watch(apiClientProvider));
    });

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepositoryImpl(
    ref.watch(notificationRemoteDatasourceProvider),
  );
});

class NotificationController extends AsyncNotifier<List<NotificationEntity>> {
  late final GetNotificationsUseCase _getNotifications;
  late final MarkAllNotificationsAsReadUseCase _markAllNotificationsAsRead;
  late final MarkNotificationAsReadUseCase _markNotificationAsRead;
  bool _isMarkingAllAsRead = false;

  bool get isMarkingAllAsRead => _isMarkingAllAsRead;

  @override
  Future<List<NotificationEntity>> build() async {
    _getNotifications = GetNotificationsUseCase(
      ref.watch(notificationRepositoryProvider),
    );
    _markNotificationAsRead = MarkNotificationAsReadUseCase(
      ref.watch(notificationRepositoryProvider),
    );
    _markAllNotificationsAsRead = MarkAllNotificationsAsReadUseCase(
      ref.watch(notificationRepositoryProvider),
    );
    return _load();
  }

  Future<List<NotificationEntity>> _load() async {
    final notifications = await _getNotifications();
    return [...notifications]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }

  Future<void> markAsRead(String notificationId) async {
    final notifications = state.value;
    if (notifications == null) return;

    final target = notifications
        .where((notification) => notification.id == notificationId)
        .firstOrNull;
    if (target == null || target.isRead) return;

    state = AsyncData(
      List<NotificationEntity>.unmodifiable(
        notifications.map(
          (notification) => notification.id == notificationId
              ? notification.copyWith(isRead: true)
              : notification,
        ),
      ),
    );

    try {
      await _markNotificationAsRead(notificationId);
    } catch (_) {
      final latest = state.value;
      if (latest != null) {
        state = AsyncData(
          List<NotificationEntity>.unmodifiable(
            latest.map(
              (notification) => notification.id == notificationId
                  ? notification.copyWith(isRead: false)
                  : notification,
            ),
          ),
        );
      }
      rethrow;
    }
  }

  Future<void> markAllAsRead() async {
    if (_isMarkingAllAsRead) return;

    final notifications = state.value;
    if (notifications == null ||
        !notifications.any((notification) => !notification.isRead)) {
      return;
    }

    _isMarkingAllAsRead = true;
    state = AsyncData(List<NotificationEntity>.unmodifiable(notifications));

    try {
      await _markAllNotificationsAsRead();

      final latest = state.value ?? notifications;
      state = AsyncData(
        List<NotificationEntity>.unmodifiable(
          latest.map((notification) => notification.copyWith(isRead: true)),
        ),
      );

      try {
        state = AsyncData(await _load());
      } catch (_) {
        // The write succeeded. Keep the locally confirmed read state if the
        // follow-up refresh is temporarily unavailable.
      }
    } finally {
      _isMarkingAllAsRead = false;
      final latest = state.value;
      if (latest != null) {
        state = AsyncData(List<NotificationEntity>.unmodifiable(latest));
      }
    }
  }
}

final notificationControllerProvider =
    AsyncNotifierProvider<NotificationController, List<NotificationEntity>>(
      NotificationController.new,
    );

final unreadNotificationCountProvider = Provider<int>((ref) {
  return ref
      .watch(notificationControllerProvider)
      .when(
        data: (notifications) =>
            notifications.where((notification) => !notification.isRead).length,
        error: (_, _) => 0,
        loading: () => 0,
      );
});

final notificationMarkAllReadInProgressProvider = Provider<bool>((ref) {
  ref.watch(notificationControllerProvider);
  return ref.read(notificationControllerProvider.notifier).isMarkingAllAsRead;
});
