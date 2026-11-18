import 'package:dio/dio.dart';
import 'package:fitnep/core/network/api_client.dart';
import 'package:fitnep/core/storage/token_storage.dart';
import 'package:fitnep/features/notifications/data/datasources/notification_destination_remote_datasource.dart';
import 'package:fitnep/features/notifications/domain/entities/notification_entity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cases = <(NotificationType, String, String, String)>[
    (NotificationType.dietPlan, 'plan-1', 'diet-plans/plan-1', 'diet_plan'),
    (
      NotificationType.message,
      'conversation-1',
      'conversations/conversation-1',
      'conversation',
    ),
    (NotificationType.task, 'task-1', 'tasks/task-1', 'task'),
    (NotificationType.payment, 'payment-1', 'payments/payment-1', 'payment'),
  ];

  for (final testCase in cases) {
    test('loads the referenced ${testCase.$1.name} record', () async {
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
                    testCase.$4: {
                      'id': testCase.$2,
                      'title': 'Referenced record',
                      'status': 'active',
                    },
                  },
                },
              ),
            );
          },
        ),
      );
      final datasource = NotificationDestinationRemoteDatasourceImpl(
        ApiClient(tokenStorage: const TokenStorage(), dio: dio),
      );

      final record = await datasource.getRecord(testCase.$1, testCase.$2);

      expect(capturedRequest.method, 'GET');
      expect(
        capturedRequest.uri.toString(),
        'https://api.fitnep.test/${testCase.$3}',
      );
      expect(record.id, testCase.$2);
      expect(record.title, 'Referenced record');
    });
  }

  test('maps deleted records to a mobile-friendly not-found error', () async {
    final datasource = _datasourceWithFailure(statusCode: 404);

    await expectLater(
      datasource.getRecord(NotificationType.task, 'deleted-task'),
      throwsA(
        isA<NotificationDestinationException>()
            .having(
              (error) => error.failure,
              'failure',
              NotificationDestinationFailure.notFound,
            )
            .having((error) => error.message, 'message', contains('deleted')),
      ),
    );
  });

  test('maps forbidden records to an access error', () async {
    final datasource = _datasourceWithFailure(statusCode: 403);

    await expectLater(
      datasource.getRecord(NotificationType.payment, 'payment-1'),
      throwsA(
        isA<NotificationDestinationException>().having(
          (error) => error.failure,
          'failure',
          NotificationDestinationFailure.forbidden,
        ),
      ),
    );
  });

  test('maps connection failures to a retryable network error', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.fitnep.test/'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
              message: 'Offline',
            ),
          );
        },
      ),
    );
    final datasource = NotificationDestinationRemoteDatasourceImpl(
      ApiClient(tokenStorage: const TokenStorage(), dio: dio),
    );

    await expectLater(
      datasource.getRecord(NotificationType.dietPlan, 'plan-1'),
      throwsA(
        isA<NotificationDestinationException>()
            .having(
              (error) => error.failure,
              'failure',
              NotificationDestinationFailure.network,
            )
            .having((error) => error.canRetry, 'canRetry', isTrue),
      ),
    );
  });
}

NotificationDestinationRemoteDatasourceImpl _datasourceWithFailure({
  required int statusCode,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.fitnep.test/'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.reject(
          DioException(
            requestOptions: options,
            response: Response<Object?>(
              requestOptions: options,
              statusCode: statusCode,
            ),
            type: DioExceptionType.badResponse,
          ),
        );
      },
    ),
  );
  return NotificationDestinationRemoteDatasourceImpl(
    ApiClient(tokenStorage: const TokenStorage(), dio: dio),
  );
}
