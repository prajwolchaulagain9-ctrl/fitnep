import 'package:dio/dio.dart';
import 'package:fitnep/core/network/api_client.dart';
import 'package:fitnep/core/storage/token_storage.dart';
import 'package:fitnep/features/health_assessment/data/datasources/client_intake_remote_datasource.dart';
import 'package:fitnep/features/health_assessment/data/repositories/client_intake_repository_impl.dart';
import 'package:fitnep/features/health_assessment/domain/entities/client_intake.dart';
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
                      'status': 'submitted',
                      'review_action': null,
                      'review_note': null,
                      'review_updated_at': null,
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
      expect(intake.status, ClientIntakeStatus.submitted);
    },
  );

  test(
    'sends the displayed version with a review and parses the updated status',
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
                      'allergies': <String>[],
                      'medical_conditions': <String>[],
                      'sections': <Object?>[],
                      'submitted_at': '2026-11-20T08:00:00.000Z',
                      'updated_at': null,
                      'status': 'information_requested',
                      'review_action': 'missing_information',
                      'review_note': 'Please provide your medication dosage.',
                      'review_updated_at': '2026-11-25T10:00:00.000Z',
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

      final intake = await ClientIntakeRepositoryImpl(datasource).updateReview(
        clientId: 'client-1',
        action: ClientIntakeReviewAction.missingInformation,
        note: 'Please provide your medication dosage.',
        expectedVersion: 2,
      );

      expect(captured.method, 'PATCH');
      expect(
        captured.uri.toString(),
        'https://api.fitnep.test/dietitian/assigned-clients/client-1/intake/review',
      );
      expect(captured.data, {
        'action': 'missing_information',
        'note': 'Please provide your medication dosage.',
        'expected_version': 2,
      });
      expect(intake.status, ClientIntakeStatus.informationRequested);
      expect(intake.reviewAction, ClientIntakeReviewAction.missingInformation);
      expect(intake.reviewNote, 'Please provide your medication dosage.');
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
