import 'package:dio/dio.dart';
import 'package:fitnep/shared/api_client.dart';
import 'package:fitnep/shared/token_storage.dart';
import 'package:fitnep/features/notifications/data/notification_remote_datasource.dart';
import 'package:fitnep/features/notifications/data/notification_entity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fetches notifications from the authenticated-user endpoint', () async {
    late RequestOptions capturedRequest;
    final dio = Dio(BaseOptions(baseUrl: 'https://api.fitnep.test/'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          capturedRequest = options;
          handler.resolve(
            Response<Object?>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'data': {
                  'notifications': [
                    {
                      'id': 'notification-1',
                      'recipient_id': 'user-1',
                      'title': 'New message',
                      'message': 'Your dietitian sent a message.',
                      'type': 'message',
                      'reference_id': 'message-1',
                      'is_read': false,
                      'created_at': '2026-11-18T08:30:00Z',
                    },
                  ],
                },
              },
            ),
          );
        },
      ),
    );
    final datasource = NotificationRemoteDatasourceImpl(
      ApiClient(tokenStorage: const TokenStorage(), dio: dio),
    );

    final notifications = await datasource.getNotifications();

    expect(capturedRequest.method, 'GET');
    expect(
      capturedRequest.uri.toString(),
      'https://api.fitnep.test/notifications',
    );
    expect(capturedRequest.queryParameters, isEmpty);
    expect(notifications, hasLength(1));
    expect(notifications.single.type, NotificationType.message);
  });

  test('marks one notification as read through the API', () async {
    late RequestOptions capturedRequest;
    final dio = Dio(BaseOptions(baseUrl: 'https://api.fitnep.test/'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          capturedRequest = options;
          handler.resolve(
            Response<Object?>(requestOptions: options, statusCode: 204),
          );
        },
      ),
    );
    final datasource = NotificationRemoteDatasourceImpl(
      ApiClient(tokenStorage: const TokenStorage(), dio: dio),
    );

    await datasource.markAsRead('notification-1');

    expect(capturedRequest.method, 'PATCH');
    expect(
      capturedRequest.uri.toString(),
      'https://api.fitnep.test/notifications/notification-1/read',
    );
  });

  test('marks all authenticated-user notifications as read', () async {
    late RequestOptions capturedRequest;
    final dio = Dio(BaseOptions(baseUrl: 'https://api.fitnep.test/'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          capturedRequest = options;
          handler.resolve(
            Response<Object?>(requestOptions: options, statusCode: 204),
          );
        },
      ),
    );
    final datasource = NotificationRemoteDatasourceImpl(
      ApiClient(tokenStorage: const TokenStorage(), dio: dio),
    );

    await datasource.markAllAsRead();

    expect(capturedRequest.method, 'PATCH');
    expect(
      capturedRequest.uri.toString(),
      'https://api.fitnep.test/notifications/read-all',
    );
    expect(capturedRequest.queryParameters, isEmpty);
    expect(capturedRequest.data, isNull);
  });
}
