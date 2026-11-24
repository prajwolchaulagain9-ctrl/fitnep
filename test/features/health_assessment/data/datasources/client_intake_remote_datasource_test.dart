import 'package:dio/dio.dart';
import 'package:fitnep/core/network/api_client.dart';
import 'package:fitnep/core/storage/token_storage.dart';
import 'package:fitnep/features/health_assessment/data/datasources/client_intake_remote_datasource.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'loads the assigned client intake from the protected endpoint',
    () async {
      late RequestOptions captured;
      final dio = Dio(BaseOptions(baseUrl: 'https://api.fitnep.test/'));
      addTearDown(dio.close);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            captured = request;
            handler.resolve(
              Response<Object?>(
                requestOptions: request,
                data: {
                  'data': {
                    'intake': {
                      'client_id': 'client-1',
                      'allergies': ['Peanuts'],
                      'medical_conditions': ['Type 2 diabetes'],
                      'sections': [
                        {
                          'title': 'Health information',
                          'fields': [
                            {'label': 'Height', 'value': '168 cm'},
                          ],
                        },
                        {
                          'title': 'Goals',
                          'fields': [
                            {
                              'label': 'Primary goal',
                              'value': 'Improve glucose control',
                            },
                          ],
                        },
                        {
                          'title': 'Restrictions',
                          'fields': [
                            {'label': 'Dietary', 'value': 'Vegetarian'},
                          ],
                        },
                      ],
                      'submitted_at': '2026-11-20T08:00:00.000Z',
                      'updated_at': null,
                    },
                  },
                },
              ),
            );
          },
        ),
      );
      final datasource = ClientIntakeRemoteDatasourceImpl(
        ApiClient(tokenStorage: const TokenStorage(), dio: dio),
      );

      final intake = await datasource.getAssignedClientIntake('client-1');

      expect(
        captured.uri.toString(),
        'https://api.fitnep.test/dietitian/assigned-clients/client-1/intake',
      );
      expect(intake.allergies, ['Peanuts']);
      expect(intake.medicalConditions, ['Type 2 diabetes']);
      expect(intake.sections.map((section) => section.title), [
        'Health information',
        'Goals',
        'Restrictions',
      ]);
      expect(intake.sections[1].fields.single.value, 'Improve glucose control');
    },
  );

  test('maps unassigned access to a forbidden intake error', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.fitnep.test/'));
    addTearDown(dio.close);
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) => handler.reject(
          DioException(
            requestOptions: request,
            response: Response<Object?>(
              requestOptions: request,
              statusCode: 403,
            ),
            type: DioExceptionType.badResponse,
          ),
        ),
      ),
    );
    final datasource = ClientIntakeRemoteDatasourceImpl(
      ApiClient(tokenStorage: const TokenStorage(), dio: dio),
    );

    await expectLater(
      datasource.getAssignedClientIntake('client-1'),
      throwsA(
        isA<ClientIntakeException>().having(
          (error) => error.failure,
          'failure',
          ClientIntakeFailure.forbidden,
        ),
      ),
    );
  });
}
