import 'package:dio/dio.dart';
import 'package:fitnep/features/admin/data/admin_local_datasource.dart';
import 'package:fitnep/features/admin/data/client_assignment_repository.dart';
import 'package:fitnep/features/admin/data/client_entity.dart';
import 'package:fitnep/features/admin/data/staff_account_entity.dart';
import 'package:fitnep/features/admin/client_profile_controller.dart';
import 'package:fitnep/features/admin/client_list_controller.dart';
import 'package:fitnep/features/admin/pages/client_profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loads current client counts from the assignment API', () async {
    late RequestOptions captured;
    final dio = Dio(BaseOptions(baseUrl: 'https://fitnep.test/'));
    addTearDown(dio.close);
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          captured = request;
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: request,
              data: {
                'data': {
                  'counts': {'dietitian-1': 4, 'dietitian-2': 1},
                },
              },
            ),
          );
        },
      ),
    );

    final counts = await ClientAssignmentRepository(dio)
        .dietitianClientCounts();

    expect(captured.path, 'admin/client-assignments/dietitian-counts');
    expect(counts, {'dietitian-1': 4, 'dietitian-2': 1});
  });

  for (final (clientId, isActive) in [
    ('client_001', true),
    ('client_005', false),
  ]) {
    testWidgets('assigns $clientId on a narrow screen without a package', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 680);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _AssignmentApi();
      addTearDown(api.dio.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminDatasourceProvider.overrideWithValue(_AssignmentDatasource()),
            clientAssignmentRepositoryProvider.overrideWithValue(
              ClientAssignmentRepository(api.dio),
            ),
            activeDietitiansProvider.overrideWith(
              (ref) async => [
                DietitianAssignmentOption(
                  dietitian: const StaffAccount(
                    uid: 'dietitian-new',
                    name: 'Dr. Alexandrina Long Dietitian Name',
                    email: 'dietitian@fitnep.test',
                    role: StaffRole.dietitian,
                    isActive: true,
                  ),
                  currentClientCount: api.assignedDietitianId == null ? 7 : 8,
                ),
              ],
            ),
          ],
          child: MaterialApp(home: ClientProfilePage(clientId: clientId)),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      final button = find.widgetWithText(OutlinedButton, 'Assign dietitian');

      await tester.scrollUntilVisible(
        button,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Unassigned'), findsOneWidget);
      expect(
        find.textContaining('when the account is reactivated'),
        isActive ? findsNothing : findsOneWidget,
      );
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('7 active clients'), findsOneWidget);
      await tester.tap(find.text('Dr. Alexandrina Long Dietitian Name'));
      await tester.pumpAndSettle();

      expect(api.assignedDietitianId, 'dietitian-new');
      expect(api.assignedClientPath, 'admin/client-assignments/$clientId');
      expect(find.text('Dietitian assignment saved.'), findsOneWidget);
      expect(find.text('Dr. Alexandrina Long Dietitian Name'), findsOneWidget);
      expect(
        find.text('Review diet plans'),
        isActive ? findsOneWidget : findsNothing,
      );

      await tester.pump(const Duration(seconds: 4));
      await tester.tap(find.widgetWithText(OutlinedButton, 'Change dietitian'));
      await tester.pumpAndSettle();
      expect(find.text('8 active clients'), findsOneWidget);
    });
  }
}

class _AssignmentDatasource extends AdminLocalDatasource {
  @override
  Future<ClientEntity> getClientById(String id) async =>
      (await super.getClientById(id)).copyWith(
        packageName: 'No current package',
        packageId: '',
        assignedDietitianName: '',
        assignedDietitianId: '',
      );
}

class _AssignmentApi {
  _AssignmentApi() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          expect(request.method, 'PUT');
          assignedClientPath = request.path;
          assignedDietitianId =
              (request.data as Map<String, dynamic>)['dietitian_id'] as String;
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: request,
              data: const {},
            ),
          );
        },
      ),
    );
  }

  final Dio dio = Dio(BaseOptions(baseUrl: 'https://fitnep.test/'));
  String? assignedDietitianId;
  String? assignedClientPath;
}
