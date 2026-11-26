import '../support/empty_package_catalog.dart';
import '../support/offline_hosted_session.dart';

import 'dart:async';

import 'package:fitnep/core/authorization/authorization_refresh.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitnep/features/authentication/data/registration_privacy.dart';
import 'package:fitnep/app/routes/app_router.dart';
import 'package:fitnep/app/routes/app_routes.dart';
import 'package:fitnep/app/routes/route_access_gate.dart';
import 'package:fitnep/features/authorization/data/authorization_repository.dart';
import 'package:fitnep/features/authorization/domain/account.dart';
import 'package:fitnep/features/authorization/presentation/role_home_page.dart';
import 'package:fitnep/features/authentication/presentation/controllers/authentication_controller.dart';
import 'package:fitnep/features/notifications/presentation/controllers/notification_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/empty_notifications.dart';

import 'package:fitnep/features/purchases/presentation/controllers/membership_controller.dart';

class _EmptyMembership extends MembershipController {
  @override
  MembershipState build() => const MembershipState();
}

class _Firestore extends Fake implements FirebaseFirestore {}

class _Identity extends Fake implements User {
  @override
  String get uid => 'account';
  @override
  bool get emailVerified => true;
}

Map<String, dynamic> _data(FitNepRole role) => {
  'id': 'account',
  'full_name': 'Current User',
  'email': 'current@example.test',
  'role': role.name,
  'account_status': 'active',
  'created_at': '2026-11-20T00:00:00Z',
  'updated_at': '2026-11-20T00:00:00Z',
};

class _Repository extends AuthorizationRepository {
  _Repository(FitNepRole role)
    : account = FitNepAccount.fromJson(_data(role)),
      super(Dio(BaseOptions(baseUrl: 'https://fitnep.test/')), _Firestore());
  FitNepAccount account;
  final changes = StreamController<FitNepAccount?>.broadcast();
  final denied = <String>[];
  final updates = <Map<String, dynamic>>[];
  final requestedPaths = <String>[];
  final assignedQueries = <Map<String, dynamic>>[];
  bool includeAssignedClients = false;
  final auditQueries = <Map<String, dynamic>>[];
  bool denyRecords = false;
  int recordRequests = 0;
  @override
  Future<FitNepAccount> current() async => account;
  @override
  Stream<FitNepAccount?> watchAccount(String uid) => changes.stream;
  void changeRole(FitNepRole role) {
    account = FitNepAccount.fromJson(_data(role));
    changes.add(account);
  }

  void changeAuditRead(bool granted) {
    account = FitNepAccount.fromJson({
      ..._data(account.role),
      'audit_read': granted,
    });
    changes.add(account);
  }

  @override
  Future<void> checkPermission(String permission) async {
    if (!AuthorizationService(
      account.role,
      auditRead: account.auditRead,
    ).hasPermission(permission)) {
      denied.add(permission);
      throw const AuthorizationFailure(
        'You do not have permission to access this feature.',
      );
    }
  }

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? data,
    Map<String, dynamic>? query,
  }) async {
    requestedPaths.add(path);
    if (path == 'admin/audit-events') {
      final filters = query ?? const <String, dynamic>{};
      auditQueries.add(filters);
      final nextPage = filters['after'] != null;
      return {
        'events': [
          {
            'id': nextPage ? 'event-1' : 'event-2',
            'action': nextPage ? 'plan.created' : 'plan.revised',
            'actor_id': 'dietitian-1',
            'actor_name': 'Synthetic reviewer',
            'actor_role': 'dietitian',
            'outcome': 'succeeded',
            'target_type': 'plan',
            'target_id': 'plan-1',
            'status': 'draft',
            'version': nextPage ? 1 : 2,
            'occurred_at': '2026-11-26T18:15:00Z',
          },
        ],
        'next_cursor': nextPage || filters.containsKey('plan_id')
            ? null
            : 'event-2',
      };
    }
    if (path == 'admin/users' && method == 'GET') {
      return {
        'users': [
          _data(FitNepRole.admin),
          {
            ..._data(FitNepRole.client),
            'id': 'target',
            'full_name': 'Target Client',
            'email': 'target@example.test',
          },
        ],
        'next_cursor': null,
      };
    }
    if (path == 'admin/users/target' && method == 'PATCH') {
      updates.add(data!);
      return {'account': _data(FitNepRole.client)};
    }
    if (path == 'clients/assigned') {
      final filters = query ?? {};
      assignedQueries.add(filters);
      if (includeAssignedClients && filters['search'] != 'No match') {
        const asha = {
          'id': 'asha',
          'full_name': 'Asha Sharma',
          'email': 'asha@fitnep.test',
          'package_status': 'active',
          'plan_status': 'no_plan',
          'intake_status': 'submitted',
          'last_activity_at': '2026-11-24T14:00:00Z',
        };
        const hari = {
          'id': 'hari',
          'full_name': 'Hari Sharma',
          'email': 'hari@fitnep.test',
          'package_status': 'pending',
          'plan_status': 'published',
        };
        if (filters['after'] == 'asha' ||
            filters['plan_status'] == 'published') {
          return {
            'clients': [hari],
            'next_cursor': null,
          };
        }
        return {
          'clients': [asha],
          'next_cursor': 'asha',
        };
      }
      return {'clients': [], 'next_cursor': null};
    }
    if (path.contains('/records/')) {
      recordRequests++;
      if (denyRecords) {
        throw const AuthorizationFailure(
          'You do not have permission to access this feature.',
        );
      }
      return {'records': [], 'next_cursor': null};
    }
    if (path.endsWith('/diet-plans') && method == 'GET') {
      return {'plans': [], 'next_cursor': null};
    }
    if (path.endsWith('/diet-plans') && method == 'POST') {
      updates.add(data!);
      return {
        'plan': {'id': 'plan'},
      };
    }
    throw const AuthorizationFailure('Unavailable in this isolated UI test.');
  }
}

Future<ProviderContainer> _open(
  WidgetTester tester,
  _Repository repository,
  String path,
) async {
  final container = ProviderContainer(
    overrides: [
      staffPasswordChangeRequiredProvider.overrideWith((ref) async => false),
      emptyPackageCatalogOverride,
      offlineHostedSessionOverride,
      registrationAcceptedProvider.overrideWith((ref, uid) async => true),
      authenticationStateProvider.overrideWith(
        (ref) => Stream.value(_Identity()),
      ),
      authorizationRepositoryProvider.overrideWithValue(repository),
      notificationControllerProvider.overrideWith(EmptyNotifications.new),
      membershipControllerProvider.overrideWith(_EmptyMembership.new),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await repository.changes.close();
  });
  final router = container.read(appRouterProvider);
  router.go(path);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets(
    'staff audit grants govern navigation, filtering and revocation',
    (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _Repository(FitNepRole.staff);
      await _open(tester, repository, AppRoutes.staffHome);
      expect(find.text('Audit logs'), findsNothing);

      repository.changeAuditRead(true);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Audit logs'));
      await tester.pumpAndSettle();
      expect(find.text('Audit log'), findsOneWidget);
      expect(find.byTooltip('Audit history'), findsNothing);
      expect(find.textContaining('27 Nov 2026, 00:00:00 NPT'), findsOneWidget);

      await tester.tap(find.byTooltip('Filter audit events'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Actor ID'),
        'dietitian-1',
      );
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      expect(repository.auditQueries.last, {'actor_id': 'dietitian-1'});
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(repository.auditQueries.last, {
        'actor_id': 'dietitian-1',
        'after': 'event-2',
      });
      expect(find.text('plan.created'), findsOneWidget);

      await tester.tap(find.text('plan.revised'));
      await tester.pumpAndSettle();
      expect(find.text('Version  2'), findsOneWidget);
      await tester.ensureVisible(find.text('View plan timeline'));
      await tester.tap(find.text('View plan timeline'));
      await tester.pumpAndSettle();
      expect(repository.auditQueries.last, {'plan_id': 'plan-1'});
      expect(find.text('Plan timeline'), findsOneWidget);

      repository.changeAuditRead(false);
      await tester.pumpAndSettle();
      expect(find.text('Plan timeline'), findsNothing);
      expect(find.text('plan.revised'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test('every role has only its permitted menu items and valid canonical identifiers', () {
    for (final role in FitNepRole.values) {
      final menu = menusForRole(role).map((item) => item.label).toSet();
      expect(menu.contains('Users and roles'), role == FitNepRole.admin);
      expect(
        menu.contains('Assigned clients'),
        role == FitNepRole.staff || role == FitNepRole.dietitian,
      );
      expect(menu.contains('Privacy preferences'), role == FitNepRole.client);
      expect(menu.contains('My profile'), true);
    }
    for (final value in [
      null,
      '',
      'CEO',
      'Client',
      ['client', 'admin'],
    ]) {
      expect(parseRole(value), isNull);
    }
  });
  for (final role in FitNepRole.values) {
    testWidgets(
      '${role.name} login opens its dashboard and rejects restricted navigation',
      (tester) async {
        final repository = _Repository(role);
        final container = await _open(tester, repository, AppRoutes.dashboard);
        expect(
          container
              .read(appRouterProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          role == FitNepRole.client
              ? AppRoutes.clientPackages
              : dashboardForRole(role),
        );
        expect(
          find.text(
            role == FitNepRole.client
                ? 'Choose a package'
                : '${role.label} dashboard',
          ),
          findsOneWidget,
        );
        if (role != FitNepRole.admin) {
          container.read(appRouterProvider).go(AppRoutes.adminUsers);
          await tester.pumpAndSettle();
          expect(
            find.text('You do not have permission to access this feature.'),
            findsOneWidget,
          );
          expect(find.text('Users and roles'), findsNothing);
          expect(repository.denied, contains('manage_user_roles'));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets('assigned clients use server filters and load subsequent pages', (
    tester,
  ) async {
    final repository = _Repository(FitNepRole.dietitian)
      ..includeAssignedClients = true;
    await _open(tester, repository, AppRoutes.assignedClients);
    expect(find.text('Asha Sharma'), findsOneWidget);
    expect(find.text('Package: Active'), findsOneWidget);
    expect(find.text('Plan: No plan yet'), findsOneWidget);
    expect(find.text('Intake: Submitted'), findsOneWidget);
    expect(find.textContaining('Last activity:'), findsOneWidget);
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(repository.assignedQueries.last['after'], 'asha');
    expect(find.text('Hari Sharma'), findsOneWidget);
    expect(find.text('Load more'), findsNothing);

    await tester.enterText(find.byType(TextField), ' Sharma ');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(repository.assignedQueries.last['search'], 'Sharma');
    expect(repository.assignedQueries.last.containsKey('after'), false);
    final filter = find.byType(DropdownButtonFormField<String>);
    await tester.tap(filter);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Published').last);
    await tester.pumpAndSettle();
    expect(repository.assignedQueries.last, {
      'limit': '20',
      'search': 'Sharma',
      'plan_status': 'published',
    });
    expect(find.text('Plan: Published'), findsOneWidget);
    expect(find.text('Asha Sharma'), findsNothing);

    await tester.enterText(find.byType(TextField), 'No match');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(
      find.text('No assigned clients match your search and filters.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'an admin client-list entry point remains guarded for every non-admin role',
    (tester) async {
      for (final role in [
        FitNepRole.client,
        FitNepRole.staff,
        FitNepRole.dietitian,
      ]) {
        final repository = _Repository(role);
        await _open(tester, repository, AppRoutes.adminClients);
        expect(
          find.text('You do not have permission to access this feature.'),
          findsOneWidget,
        );
        expect(repository.denied, contains('manage_client_accounts'));
        expect(
          repository.requestedPaths.where(
            (path) => path.startsWith('admin/clients'),
          ),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
  testWidgets(
    'a live role change clears the forbidden page and redirects to the new dashboard',
    (tester) async {
      final repository = _Repository(FitNepRole.admin);
      final container = await _open(tester, repository, AppRoutes.adminUsers);
      expect(find.text('Target Client'), findsOneWidget);
      repository.changeRole(FitNepRole.client);
      await tester.pumpAndSettle();
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        AppRoutes.clientHome,
      );
      expect(find.text('Target Client'), findsNothing);
      expect(find.text('Your FitNep updates'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'admin role selection sends an authenticated backend operation after confirmation',
    (tester) async {
      final repository = _Repository(FitNepRole.admin);
      await _open(tester, repository, AppRoutes.adminUsers);
      final selector = find.byType(DropdownButtonFormField<FitNepRole>).last;
      await tester.ensureVisible(selector);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Staff').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(repository.updates, [
        {'role': 'staff'},
      ]);
      expect(find.text('Account updated.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('cancelling a role change preserves the displayed server role', (
    tester,
  ) async {
    final repository = _Repository(FitNepRole.admin);
    await _open(tester, repository, AppRoutes.adminUsers);
    final selector = find.byType(DropdownButtonFormField<FitNepRole>).last;
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Staff').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.updates, isEmpty);
    expect(
      tester
          .state<FormFieldState<FitNepRole>>(
            find.byType(DropdownButtonFormField<FitNepRole>).last,
          )
          .value,
      FitNepRole.client,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'role changes close administrative dialogs and remove restricted content',
    (tester) async {
      final repository = _Repository(FitNepRole.admin);
      final container = await _open(tester, repository, AppRoutes.adminUsers);
      final selector = find.byType(DropdownButtonFormField<FitNepRole>).last;
      await tester.ensureVisible(selector);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Staff').last);
      await tester.pumpAndSettle();
      expect(find.text('Confirm'), findsOneWidget);
      repository.changeRole(FitNepRole.client);
      await tester.pumpAndSettle();
      expect(find.text('Confirm'), findsNothing);
      expect(find.text('Target Client'), findsNothing);
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        AppRoutes.clientHome,
      );
      expect(repository.updates, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'a record denial leaves assigned diet-plan tools usable and does not loop on role refresh',
    (tester) async {
      final repository = _Repository(FitNepRole.dietitian)..denyRecords = true;
      final container = await _open(
        tester,
        repository,
        '/care/clients/client/records',
      );
      expect(
        find.text('You do not have permission to access this feature.'),
        findsOneWidget,
      );
      expect(find.text('Create plan'), findsOneWidget);
      container.read(authorizationRefreshProvider.notifier).refresh();
      await tester.pumpAndSettle();
      expect(repository.recordRequests, 1);
      await tester.tap(find.text('Create plan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save plan'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a plan title.'), findsOneWidget);
      expect(find.text('Enter the diet plan.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, 'Weekly plan');
      await tester.enterText(
        find.byType(TextFormField).last,
        'Assigned client nutrition plan.',
      );
      await tester.tap(find.text('Save plan'));
      await tester.pumpAndSettle();
      expect(repository.updates, [
        {
          'title': 'Weekly plan',
          'description': 'Assigned client nutrition plan.',
        },
      ]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'record screens distinguish own-client access from assigned-dietitian access',
    (tester) async {
      for (final role in [
        FitNepRole.client,
        FitNepRole.staff,
        FitNepRole.admin,
        FitNepRole.dietitian,
      ]) {
        final repository = _Repository(role);
        final container = await _open(tester, repository, AppRoutes.dashboard);
        final path = role == FitNepRole.dietitian
            ? AppRoutes.clientRecords
            : '/care/clients/client/records';
        container.read(appRouterProvider).go(path);
        await tester.pumpAndSettle();
        expect(
          find.text('You do not have permission to access this feature.'),
          findsOneWidget,
        );
        expect(find.text('Create plan'), findsNothing);
        expect(repository.recordRequests, 0);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}
