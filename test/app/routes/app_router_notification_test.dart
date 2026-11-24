import '../../support/offline_hosted_session.dart';

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitnep/app/routes/app_router.dart';
import 'package:fitnep/app/routes/app_routes.dart';
import 'package:fitnep/app/routes/route_access_gate.dart';
import 'package:fitnep/core/services/firebase_providers.dart';
import 'package:fitnep/features/notifications/domain/entities/notification_destination_record.dart';
import 'package:fitnep/features/notifications/domain/entities/notification_entity.dart';
import 'package:fitnep/features/notifications/domain/repositories/notification_destination_repository.dart';
import 'package:fitnep/features/notifications/presentation/controllers/notification_destination_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitnep/features/authorization/data/authorization_repository.dart';

import '../../support/denied_permission_repository.dart';

void main() {
  final cases = <(String, NotificationType, String)>[
    (
      AppRoutes.dietPlanDetailsName,
      NotificationType.dietPlan,
      'Diet Plan Details',
    ),
    (AppRoutes.messageThreadName, NotificationType.message, 'Messages'),
    (AppRoutes.taskDetailsName, NotificationType.task, 'Task Details'),
    (AppRoutes.paymentDetailsName, NotificationType.payment, 'Payment Details'),
  ];

  for (final testCase in cases) {
    testWidgets('registered ${testCase.$2.name} route passes the record ID', (
      tester,
    ) async {
      final repository = _FakeDestinationRepository();
      final container = ProviderContainer(
        overrides: [
          offlineHostedSessionOverride,
          routeSessionProvider.overrideWith(
            (ref) async => (uid: 'dietitian-1', role: FitNepRole.dietitian),
          ),
          notificationDestinationRepositoryProvider.overrideWithValue(
            repository,
          ),
        ],
      );
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);
      router.goNamed(testCase.$1, pathParameters: const {'id': 'record-99'});

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(testCase.$3), findsOneWidget);
      expect(find.text('Reference: record-99'), findsOneWidget);
      expect(repository.lastType, testCase.$2);
      expect(repository.lastReferenceId, 'record-99');
    });
  }

  testWidgets('direct links enforce role changes and sign-out', (tester) async {
    final auth = _RouteAuth();
    addTearDown(auth.users.close);
    final repository = _FakeDestinationRepository();
    final sessions = StreamProvider<RouteSession?>(
      (ref) => auth.users.stream.map(
        (user) => user == null
            ? null
            : (uid: user.uid, role: parseRole((user as _RouteUser).role)),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        offlineHostedSessionOverride,
        firebaseInitializationProvider.overrideWith((ref) async {}),
        firebaseAuthProvider.overrideWithValue(auth),
        authorizationRepositoryProvider.overrideWithValue(
          DeniedPermissionRepository(),
        ),
        routeSessionProvider.overrideWith((ref) async {
          final state = ref.watch(sessions);
          return state.isLoading
              ? await ref.watch(sessions.future)
              : state.requireValue;
        }),
        notificationDestinationRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);
    router.goNamed(AppRoutes.messageThreadName, pathParameters: {'id': 'one'});

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    auth.users.add(null);
    await tester.pumpAndSettle();
    expect(find.text('Sign in required'), findsOneWidget);

    auth.users.add(_RouteUser('unassigned'));
    await tester.pumpAndSettle();
    expect(find.text('Access denied'), findsOneWidget);
    expect(repository.lastReferenceId, isNull);

    auth.users.add(_RouteUser('dietitian'));
    await tester.pumpAndSettle();
    expect(find.text('Loaded record'), findsOneWidget);

    for (final path in [
      AppRoutes.adminClients,
      AppRoutes.adminStaffAccounts,
      AppRoutes.adminStaffHistory,
      AppRoutes.adminPackages,
      AppRoutes.adminPackageHistory,
      AppRoutes.adminCreatePackage,
      AppRoutes.adminEditPackage('package-1'),
      AppRoutes.clientPackages,
      AppRoutes.clientMembership,
    ]) {
      router.go(path);
      await tester.pumpAndSettle();
      expect(find.text('Access denied'), findsOneWidget, reason: path);
      expect(tester.takeException(), isNull, reason: path);
    }

    auth.users.add(null);
    await tester.pumpAndSettle();
    expect(find.text('Sign in required'), findsOneWidget);
  });
}

class _RouteAuth extends Fake implements FirebaseAuth {
  final users = StreamController<User?>();
  User? _currentUser;

  @override
  User? get currentUser => _currentUser;

  @override
  Stream<User?> idTokenChanges() async* {
    await for (final user in users.stream) {
      _currentUser = user;
      yield user;
    }
  }
}

class _RouteUser extends Fake implements User {
  _RouteUser(this.role);

  final String role;

  @override
  String get uid => 'account-1';

  @override
  Future<IdTokenResult> getIdTokenResult([bool forceRefresh = false]) async =>
      _RoleToken(role);
}

class _RoleToken extends Fake implements IdTokenResult {
  _RoleToken(this.role);

  final String role;

  @override
  Map<String, dynamic> get claims => {'role': role};
}

class _FakeDestinationRepository implements NotificationDestinationRepository {
  NotificationType? lastType;
  String? lastReferenceId;

  @override
  Future<NotificationDestinationRecord> getRecord(
    NotificationType type,
    String referenceId,
  ) async {
    lastType = type;
    lastReferenceId = referenceId;
    return NotificationDestinationRecord(
      id: referenceId,
      title: 'Loaded record',
      description: null,
      fields: const [],
    );
  }
}
