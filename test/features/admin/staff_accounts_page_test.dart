import '../../support/offline_hosted_session.dart';

import 'package:dio/dio.dart';
import 'package:fitnep/app/routes/app_router.dart';
import 'package:fitnep/app/routes/app_routes.dart';
import 'package:fitnep/app/routes/route_access_gate.dart';
import 'package:fitnep/features/admin/data/repositories/staff_account_repository.dart';
import 'package:fitnep/features/admin/presentation/widgets/staff_records_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('admin creates, edits and changes a staff account status', (
    tester,
  ) async {
    final api = _StaffApi();
    final container = ProviderContainer(
      overrides: [
        offlineHostedSessionOverride,
        routeSessionProvider.overrideWith(
          (ref) async =>
              (uid: 'admin-1', role: FitNepRole.admin, auditRead: false),
        ),
        staffAccountRepositoryProvider('admin-1')
            .overrideWithValue(StaffAccountRepository(api.dio)),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(api.dio.close);
    final router = container.read(appRouterProvider)
      ..go(AppRoutes.adminStaffAccounts);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No staff accounts found.'), findsOneWidget);

    await tester.tap(find.text('Create staff account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Team Member');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'Team@fitnep.test',
    );
    await tester.enterText(
      find.byType(TextFormField).at(2),
      'TemporaryPass123!',
    );
    final password = find.byType(EditableText).at(2);
    expect(tester.widget<EditableText>(password).obscureText, isTrue);
    await tester.tap(find.byTooltip('Show temporary password'));
    await tester.pump();
    expect(tester.widget<EditableText>(password).obscureText, isFalse);
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('Team Member'), findsOneWidget);
    final create = api.writes.single;
    expect(create.method, 'POST');
    expect(create.data, containsPair('email', 'team@fitnep.test'));
    expect(create.data, containsPair('role', 'staff'));
    expect(
      create.data,
      containsPair('temporary_password', 'TemporaryPass123!'),
    );
    expect(create.data['request_id'], isNotEmpty);

    await tester.tap(find.byTooltip('Manage Team Member'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit account'));
    await tester.pumpAndSettle();
    expect(find.text('Temporary password'), findsNothing);
    await tester.enterText(find.byType(TextFormField).first, 'Updated Member');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(find.text('Updated Member'), findsOneWidget);
    expect(api.writes.last.data, containsPair('name', 'Updated Member'));
    expect(api.writes.last.data, isNot(contains('temporary_password')));

    for (final (action, active) in [
      ('Deactivate', false),
      ('Reactivate', true),
    ]) {
      await tester.tap(find.byTooltip('Manage Updated Member'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, action));
      await tester.pumpAndSettle();
      expect(api.writes.last.path, 'admin/staff-accounts/team-1/active');
      expect(api.writes.last.data, containsPair('is_active', active));
      expect(
        find.text(
          'team@fitnep.test • Staff • ${active ? 'Active' : 'Inactive'}',
        ),
        findsOneWidget,
      );
    }

    await tester.tap(find.byTooltip('Staff account history'));
    await tester.pumpAndSettle();
    expect(find.text('Account reactivated'), findsOneWidget);
    await tester.tap(find.text('Account reactivated'));
    await tester.pumpAndSettle();
    expect(find.text('Inactive → Active'), findsOneWidget);
  });
  testWidgets('retrying a later page keeps the rows already loaded', (
    tester,
  ) async {
    final calls = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StaffRecordsList<String>(
            emptyMessage: 'Empty',
            buildItem: Text.new,
            load: (cursor) async {
              calls.add(cursor);
              if (cursor == null) {
                return (items: ['First'], nextCursor: 'second');
              }
              if (calls.length == 2) throw const StaffAccountFailure('Offline');
              return (items: ['Second'], nextCursor: null);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(calls, [null, 'second', 'second']);
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
  });
}

class _StaffApi {
  _StaffApi() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          final Map<String, dynamic> data;
          if (request.path.endsWith('/history')) {
            data = {
              'entries': [
                {
                  'id': 'event-1',
                  'action': 'reactivated',
                  'actor_uid': 'admin-1',
                  'actor_name': 'Demo Admin',
                  'before': {...account!, 'is_active': false},
                  'after': account,
                  'completed_at': '2026-11-21T09:30:00Z',
                },
              ],
              'next_cursor': null,
            };
          } else if (request.method == 'GET') {
            // A mixed-role Auth page can contain no staff accounts.
            data = request.queryParameters['cursor'] == null
                ? {'accounts': [], 'next_cursor': 'next-page'}
                : {
                    'accounts': [?account],
                    'next_cursor': null,
                  };
          } else {
            writes.add(request);
            final changes = Map<String, dynamic>.from(request.data as Map)
              ..remove('request_id')
              ..remove('temporary_password');
            account = {
              'uid': 'team-1',
              'is_active': true,
              ...?account,
              ...changes,
            };
            data = {'account': account};
          }
          handler.resolve(
            Response(requestOptions: request, data: {'data': data}),
          );
        },
      ),
    );
  }

  final dio = Dio(BaseOptions(baseUrl: 'https://fitnep.test/'));
  final writes = <RequestOptions>[];
  Map<String, dynamic>? account;
}
