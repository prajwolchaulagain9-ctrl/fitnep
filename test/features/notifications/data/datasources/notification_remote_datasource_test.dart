import 'package:dio/dio.dart';
import 'package:fitnep/core/network/api_client.dart';
import 'package:fitnep/core/storage/token_storage.dart';
import 'package:fitnep/features/notifications/data/datasources/notification_remote_datasource.dart';
import 'package:fitnep/features/notifications/domain/entities/notification_entity.dart';
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
}
