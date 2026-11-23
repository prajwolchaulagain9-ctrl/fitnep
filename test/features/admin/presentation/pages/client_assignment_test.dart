import 'package:dio/dio.dart';
import 'package:fitnep/features/admin/data/repositories/client_assignment_repository.dart';
import 'package:fitnep/features/admin/domain/entities/staff_account_entity.dart';
import 'package:fitnep/features/admin/presentation/controllers/client_profile_controller.dart';
import 'package:fitnep/features/admin/presentation/pages/client_profile_page.dart';
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

  testWidgets('active-package client can be assigned', (tester) async {
    final api = _AssignmentApi(canAssign: true, packageStatus: 'active');
    addTearDown(api.dio.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clientAssignmentRepositoryProvider.overrideWithValue(
            ClientAssignmentRepository(api.dio),
          ),
          activeDietitiansProvider.overrideWith(
            (ref) async => [
              DietitianAssignmentOption(
                dietitian: const StaffAccount(
                  uid: 'dietitian-new',
                  name: 'Dr. Active Dietitian',
                  email: 'dietitian@fitnep.test',
                  role: StaffRole.dietitian,
                  isActive: true,
                ),
                currentClientCount: api.assignedDietitianId == null ? 7 : 8,
              ),
            ],
          ),
        ],
        child: const MaterialApp(
          home: ClientProfilePage(clientId: 'client_001'),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Dietitian Assignment'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    final button = find.widgetWithText(OutlinedButton, 'Change Dietitian');
    expect(button, findsOneWidget);
    expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);

    await tester.scrollUntilVisible(
      button,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('7 current clients'), findsOneWidget);
    await tester.tap(find.text('Dr. Active Dietitian'));
    await tester.pumpAndSettle();

    expect(api.assignedDietitianId, 'dietitian-new');
    expect(find.text('Client assigned successfully.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('8 current clients'), findsOneWidget);
  });

  testWidgets('inactive-package client is blocked with an explanation', (
    tester,
  ) async {
    final api = _AssignmentApi(canAssign: false, packageStatus: 'expired');
    addTearDown(api.dio.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clientAssignmentRepositoryProvider.overrideWithValue(
            ClientAssignmentRepository(api.dio),
          ),
        ],
        child: const MaterialApp(
          home: ClientProfilePage(clientId: 'client_001'),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Dietitian Assignment'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text(inactivePackageAssignmentMessage), findsOneWidget);
    final button = find.widgetWithText(OutlinedButton, 'Change Dietitian');
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    expect(api.assignedDietitianId, isNull);
  });
}

class _AssignmentApi {
  _AssignmentApi({required this.canAssign, required this.packageStatus}) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          if (request.method == 'GET') {
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: request,
                data: {
                  'data': {
                    'eligibility': {
                      'client_id': 'client_001',
                      'package_status': packageStatus,
                      'can_assign': canAssign,
                      'message': canAssign
                          ? null
                          : inactivePackageAssignmentMessage,
                    },
                  },
                },
              ),
            );
            return;
          }
          assignedDietitianId =
              (request.data as Map<String, dynamic>)['dietitian_id'] as String;
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: request,
              data: {
                'data': {
                  'assignment': {
                    'client_id': 'client_001',
                    'dietitian_id': assignedDietitianId,
                    'active': true,
                    'assigned_at': '2026-11-23T12:00:00.000Z',
                  },
                },
              },
            ),
          );
        },
      ),
    );
  }

  final bool canAssign;
  final String packageStatus;
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://fitnep.test/'));
  String? assignedDietitianId;
}
