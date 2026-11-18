import 'package:dio/dio.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/api_client.dart';
import '../models/notification_model.dart';

abstract class NotificationRemoteDatasource {
  Future<List<NotificationModel>> getNotifications();

  Future<void> markAsRead(String notificationId);

  Future<void> markAllAsRead();
}

class NotificationRemoteDatasourceImpl implements NotificationRemoteDatasource {
  final ApiClient _apiClient;

  const NotificationRemoteDatasourceImpl(this._apiClient);

  @override
  Future<List<NotificationModel>> getNotifications() async {
    _ensureConfigured();

    try {
      final response = await _apiClient.dio.get<Object?>(
        AppConstants.notificationsEndpoint,
      );
      final items = _extractItems(response.data);
      return items
          .map((item) => NotificationModel.fromJson(item))
          .toList(growable: false);
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode;
      if (statusCode == 401) {
        throw const NotificationDataException(
          'Your session has expired. Please sign in again.',
        );
      }
      if (statusCode == 403) {
        throw const NotificationDataException(
          'You do not have permission to view these notifications.',
        );
      }
      throw const NotificationDataException(
        'Unable to load notifications. Check your connection and try again.',
      );
    } on FormatException {
      throw const NotificationDataException(
        'The notification service returned invalid data.',
      );
    }
  }

  @override
  Future<void> markAsRead(String notificationId) async {
    _ensureConfigured();

    try {
      await _apiClient.dio.patch<Object?>(
        AppConstants.notificationReadEndpoint(notificationId),
      );
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode;
      if (statusCode == 401) {
        throw const NotificationDataException(
          'Your session has expired. Please sign in again.',
        );
      }
      if (statusCode == 403) {
        throw const NotificationDataException(
          'You do not have permission to update this notification.',
        );
      }
      if (statusCode == 404) {
        throw const NotificationDataException(
          'This notification is no longer available.',
        );
      }
      throw const NotificationDataException(
        'Could not mark the notification as read. Check your connection and try again.',
      );
    }
  }

  @override
  Future<void> markAllAsRead() async {
    _ensureConfigured();

    try {
      await _apiClient.dio.patch<Object?>(
        AppConstants.notificationsReadAllEndpoint,
      );
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode;
      if (statusCode == 401) {
        throw const NotificationDataException(
          'Your session has expired. Please sign in again.',
        );
      }
      if (statusCode == 403) {
        throw const NotificationDataException(
          'You do not have permission to update these notifications.',
        );
      }
      if (statusCode == 404) {
        throw const NotificationDataException(
          'Mark all as read is not available right now.',
        );
      }
      throw const NotificationDataException(
        'Could not mark all notifications as read. Check your connection and try again.',
      );
    }
  }

  void _ensureConfigured() {
    if (_apiClient.dio.options.baseUrl.trim().isEmpty) {
      throw const NotificationDataException(
        'Notification service is not configured.',
      );
    }
  }

  List<Map<String, dynamic>> _extractItems(Object? responseData) {
    Object? payload = responseData;

    if (payload is Map) {
      payload = payload['notifications'] ?? payload['data'];
    }
    if (payload is Map) {
      payload = payload['notifications'] ?? payload['data'];
    }
    if (payload is! List) {
      throw const FormatException('Expected a notification list.');
    }

    return payload
        .map((item) {
          if (item is! Map) {
            throw const FormatException('Invalid notification item.');
          }
          return Map<String, dynamic>.from(item);
        })
        .toList(growable: false);
  }
}

class NotificationDataException implements Exception {
  final String message;

  const NotificationDataException(this.message);

  @override
  String toString() => message;
}
