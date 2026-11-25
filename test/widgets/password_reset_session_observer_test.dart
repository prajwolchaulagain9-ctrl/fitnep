import '../support/offline_hosted_session.dart';

import 'package:fitnep/features/authentication/data/registration_privacy.dart';

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitnep/app/app.dart';
import 'package:fitnep/app/routes/app_router.dart';
import 'package:fitnep/app/routes/app_routes.dart';
import 'package:fitnep/core/services/firebase_providers.dart';
import 'package:fitnep/features/authentication/presentation/controllers/authentication_controller.dart';
import 'package:fitnep/features/notifications/domain/entities/notification_entity.dart';
import 'package:fitnep/features/notifications/domain/repositories/notification_repository.dart';
import 'package:fitnep/features/notifications/presentation/controllers/notification_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_session_preference_store.dart';

class _User extends Fake implements User {
  @override
  bool get emailVerified => true;
  FirebaseAuthException? error;
  int refreshes = 0;
  @override
  String get uid => 'client';
  @override
  String get refreshToken => 'test-refresh-token';
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    expect(forceRefresh, isTrue);
    refreshes++;
    if (error != null) throw error!;
    return 'test-id-token';
  }
}

class _Auth extends Fake implements FirebaseAuth {
  _Auth(this.user);
  _User? user;
  final changes = StreamController<User?>.broadcast();
  @override
  User? get currentUser => user;
  @override
  Stream<User?> authStateChanges() async* {
    yield user;
    yield* changes.stream;
  }

  @override
  Future<void> signOut() async {
    user = null;
    changes.add(null);
  }
}

Future<ProviderContainer> _open(
  WidgetTester tester,
  _Auth auth, {
  NotificationRepository? notifications,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        offlineHostedSessionOverride,
        staffPasswordChangeRequiredProvider.overrideWith((ref) async => false),
        registrationAcceptedProvider.overrideWith((ref, uid) async => true),
        firebaseInitializationProvider.overrideWith((ref) async {}),
        firebaseAuthProvider.overrideWithValue(auth),
        sessionPreferenceStoreProvider.overrideWithValue(
          MemorySessionPreferenceStore(rememberSession: true),
        ),
        if (notifications != null)
          notificationRepositoryProvider.overrideWithValue(notifications),
      ],
      child: const FitNepApp(),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(FitNepApp)),
  );
  container.read(appRouterProvider).goNamed(AppRoutes.about);
  await tester.pumpAndSettle();
  return container;
}

class _Notifications implements NotificationRepository {
  _Notifications(this.auth);
  final _Auth auth;
  int loads = 0;
  @override
  Future<List<NotificationEntity>> getNotifications() async {
    loads++;
    return auth.currentUser == null
        ? []
        : [
            NotificationEntity(
              id: 'old-account-notification',
              recipientId: 'client',
              title: 'Private',
              message: 'Account update',
              type: NotificationType.message,
              referenceId: 'conversation',
              isRead: false,
              createdAt: DateTime.utc(2026),
            ),
          ];
  }

  @override
  Future<void> markAsRead(String notificationId) async {}
  @override
  Future<void> markAllAsRead() async {}
}

Future<void> _close(WidgetTester tester, _Auth auth) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await auth.changes.close();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

void main() {
  testWidgets('revocation clears notifications cached for the old account', (
    tester,
  ) async {
    final user = _User();
    final auth = _Auth(user);
    final notifications = _Notifications(auth);
    final container = await _open(tester, auth, notifications: notifications);
    expect(
      await container.read(notificationControllerProvider.future),
      hasLength(1),
    );
    user.error = FirebaseAuthException(code: 'user-token-expired');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(auth.currentUser == null, isTrue);
    expect(
      await container.read(notificationControllerProvider.future),
      isEmpty,
    );
    expect(notifications.loads, 2);
    await _close(tester, auth);
  });
  testWidgets('revoked session is cleared on resume and returns to login', (
    tester,
  ) async {
    final user = _User();
    final auth = _Auth(user);
    await _open(tester, auth);
    user.error = FirebaseAuthException(code: 'user-token-expired');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(auth.currentUser == null, isTrue);
    expect(find.text('Welcome back'), findsOneWidget);
    await _close(tester, auth);
  });

  testWidgets('foreground refresh detects revocation without leaving the app', (
    tester,
  ) async {
    final user = _User();
    final auth = _Auth(user);
    await _open(tester, auth);
    user.error = FirebaseAuthException(code: 'user-token-expired');
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(auth.currentUser == null, isTrue);
    expect(find.text('Welcome back'), findsOneWidget);
    await _close(tester, auth);
  });

  testWidgets(
    'background pauses refresh and network failure preserves the session',
    (tester) async {
      final user = _User();
      final auth = _Auth(user);
      await _open(tester, auth);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final before = user.refreshes;
      await tester.pump(const Duration(seconds: 61));
      expect(user.refreshes, before);
      user.error = FirebaseAuthException(code: 'network-request-failed');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(auth.currentUser?.uid, 'client');
      expect(find.text('About FitNEP'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _close(tester, auth);
    },
  );
}
