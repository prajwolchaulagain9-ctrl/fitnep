import 'package:fitnep/features/packages/data/package_repository.dart';

import '../../support/offline_hosted_session.dart';

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitnep/app/routes/app_router.dart';
import 'package:fitnep/app/routes/app_routes.dart';
import 'package:fitnep/app/routes/route_access_gate.dart';
import 'package:fitnep/shared/firebase_providers.dart';
import 'package:fitnep/features/health_assessment/data/client_intake.dart';
import 'package:fitnep/features/health_assessment/data/client_intake_repository.dart';
import 'package:fitnep/features/health_assessment/client_intake_controller.dart';
import 'package:fitnep/features/notifications/data/notification_destination_record.dart';
import 'package:fitnep/features/notifications/data/notification_entity.dart';
import 'package:fitnep/features/notifications/data/notification_destination_repository.dart';
import 'package:fitnep/features/notifications/notification_destination_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitnep/features/authorization/data/authorization_repository.dart';

import '../../support/denied_permission_repository.dart';

void main() {
  testWidgets('payment notification opens the requested payment details', (
    tester,
  ) async {
    String? paymentId;
    final container = ProviderContainer(
      overrides: [
        offlineHostedSessionOverride,
        routeSessionProvider.overrideWith(
          (ref) async => (
            uid: 'admin-1',
            role: FitNepRole.admin,
            auditRead: false,
            paymentsVerify: true,
          ),
        ),
        paymentDetailsProvider.overrideWith((ref, id) async {
          paymentId = id;
          throw const PackageFailure('Test payment response');
        }),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);
    router.goNamed(
      AppRoutes.paymentDetailsName,
      pathParameters: {'id': 'payment-99'},
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(paymentId, 'payment-99');
    expect(find.text('Payment details'), findsOneWidget);
  });

  final cases = <(String, NotificationType, String)>[
    (
      AppRoutes.dietPlanDetailsName,
      NotificationType.dietPlan,
      'Diet Plan Details',
    ),
    (AppRoutes.messageThreadName, NotificationType.message, 'Messages'),
    (AppRoutes.taskDetailsName, NotificationType.task, 'Task Details'),
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
            (ref) async => (
              uid: 'dietitian-1',
              role: FitNepRole.dietitian,
              auditRead: false,
              paymentsVerify: false,
            ),
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

  testWidgets(
    'assigned dietitian opens the complete intake with priority health alerts first',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer(
        overrides: [
          offlineHostedSessionOverride,
          routeSessionProvider.overrideWith(
            (ref) async => (
              uid: 'dietitian-1',
              role: FitNepRole.dietitian,
              auditRead: false,
              paymentsVerify: false,
            ),
          ),
          notificationDestinationRepositoryProvider.overrideWithValue(
            _FakeDestinationRepository(),
          ),
          clientIntakeRepositoryProvider.overrideWithValue(
            _FakeClientIntakeRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);
      router.goNamed(
        AppRoutes.dietitianAssignedClientName,
        pathParameters: const {'id': 'client-1'},
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Open full intake form'), findsOneWidget);
      expect(find.text('Open records and diet plans'), findsOneWidget);
      await tester.tap(find.text('Open full intake form'));
      await tester.pumpAndSettle();

      expect(find.text('Client intake form'), findsOneWidget);
      expect(find.text('Allergies'), findsOneWidget);
      expect(find.text('Peanuts'), findsOneWidget);
      expect(find.text('Medical conditions'), findsOneWidget);
      expect(find.text('Type 2 diabetes'), findsOneWidget);
      expect(find.text('Health information'), findsOneWidget);
      expect(find.text('Goals'), findsOneWidget);
      expect(find.text('Restrictions'), findsOneWidget);
      expect(find.text('168 cm'), findsOneWidget);
      expect(find.text('Improve glucose control'), findsOneWidget);
      expect(find.text('Vegetarian'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Allergies')).dy,
        lessThan(tester.getTopLeft(find.text('Health information')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Medical conditions')).dy,
        lessThan(tester.getTopLeft(find.text('Health information')).dy),
      );
    },
  );

  testWidgets('direct links enforce role changes and sign-out', (tester) async {
    final auth = _RouteAuth();
    addTearDown(auth.users.close);
    final repository = _FakeDestinationRepository();
    final sessions = StreamProvider<RouteSession?>(
      (ref) => auth.users.stream.map(
        (user) => user == null
            ? null
            : (
                uid: user.uid,
                role: parseRole((user as _RouteUser).role),
                auditRead: false,
                paymentsVerify: false,
              ),
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

class _FakeClientIntakeRepository implements ClientIntakeRepository {
  @override
  Future<ClientIntake> updateReview({
    required String clientId,
    required ClientIntakeReviewAction action,
    String? note,
    int? expectedVersion,
    int? expectedReviewRevision,
  }) => getAssignedClientIntake(clientId);

  @override
  Future<ClientIntake> getAssignedClientIntake(String clientId) async {
    return ClientIntake(
      clientId: clientId,
      allergies: const ['Peanuts'],
      medicalConditions: const ['Type 2 diabetes'],
      submittedAt: DateTime.parse('2026-11-20T08:00:00.000Z'),
      updatedAt: null,
      sections: const [
        ClientIntakeSection(
          title: 'Health information',
          fields: [ClientIntakeField(label: 'Height', value: '168 cm')],
        ),
        ClientIntakeSection(
          title: 'Goals',
          fields: [
            ClientIntakeField(
              label: 'Primary goal',
              value: 'Improve glucose control',
            ),
          ],
        ),
        ClientIntakeSection(
          title: 'Restrictions',
          fields: [ClientIntakeField(label: 'Dietary', value: 'Vegetarian')],
        ),
      ],
    );
  }
}
