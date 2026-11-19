import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fitnep/app/app.dart';
import 'package:fitnep/app/routes/app_router.dart';
import 'package:fitnep/features/authentication/data/password_recovery_service.dart';
import 'package:fitnep/firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('FITNEP_LIVE_RECOVERY_TEST');
  const nonce = String.fromEnvironment('FITNEP_TEST_NONCE');
  testWidgets(
    'live recovery resets credentials and ends existing sessions',
    (tester) async {
      final client = Dio(
        BaseOptions(
          baseUrl: 'http://127.0.0.1:8765',
          headers: {'X-FitNEP-Test': nonce},
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 45),
        ),
      );
      Future<Map<String, dynamic>> call(String path, [Object? data]) async {
        final response = await tester.runAsync(
          () => client.post<Map<String, dynamic>>(path, data: data),
        );
        return response!.data!;
      }

      Future<void> waitFor(String text) async {
        final deadline = DateTime.now().add(const Duration(seconds: 60));
        while (find.text(text).evaluate().isEmpty &&
            DateTime.now().isBefore(deadline)) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 250)),
          );
          await tester.pump();
        }
        expect(find.text(text), findsOneWidget);
      }

      final fixture = await call('/fixture');
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      final auth = FirebaseAuth.instance;
      await auth.signInWithEmailAndPassword(
        email: fixture['email'] as String,
        password: fixture['password'] as String,
      );
      final secondApp = await Firebase.initializeApp(
        name: 'fitnep-recovery-secondary-test',
        options: DefaultFirebaseOptions.currentPlatform,
      );
      final secondAuth = FirebaseAuth.instanceFor(app: secondApp);
      await secondAuth.signInWithEmailAndPassword(
        email: fixture['email'] as String,
        password: fixture['password'] as String,
      );
      try {
        await call('/capture', {
          'idToken': await auth.currentUser!.getIdToken(),
        });
        await tester.pumpWidget(const ProviderScope(child: FitNepApp()));
        await waitFor('Learn about FitNEP');
        final container = ProviderScope.containerOf(
          tester.element(find.byType(FitNepApp)),
        );
        container.read(appRouterProvider).go('/forgot-password');
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextFormField),
          fixture['email'] as String,
        );
        await tester.ensureVisible(find.text('Send reset link'));
        await tester.tap(find.text('Send reset link'));
        await waitFor('Check your email');
        final action = await call('/reset-code');
        container
            .read(appRouterProvider)
            .go('/reset-password?mode=resetPassword&oobCode=${action['code']}');
        await waitFor('Create a new password');
        final fields = find.byType(TextFormField);
        await tester.enterText(fields.at(0), 'abc');
        await tester.enterText(fields.at(1), 'abc');
        await tester.ensureVisible(find.text('Update password'));
        await tester.tap(find.text('Update password'));
        final weakExplanation = find.textContaining('Your password needs');
        final deadline = DateTime.now().add(const Duration(seconds: 60));
        while (weakExplanation.evaluate().isEmpty &&
            DateTime.now().isBefore(deadline)) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 250)),
          );
          await tester.pump();
        }
        expect(weakExplanation, findsOneWidget);
        await tester.enterText(fields.at(0), fixture['nextPassword'] as String);
        await tester.enterText(fields.at(1), fixture['nextPassword'] as String);
        await tester.ensureVisible(find.text('Update password'));
        await tester.tap(find.text('Update password'));
        await waitFor('Password updated');
        expect(
          auth.currentUser == null,
          isTrue,
          reason: 'Reset must sign out the current native client.',
        );
        await PasswordRecoveryService(secondAuth).signOutIfSessionRevoked();
        expect(
          secondAuth.currentUser == null,
          isTrue,
          reason: 'The second native session must end.',
        );
        await call('/probe');
        // Leave the completed route before opening the used link as a new flow.
        container.read(appRouterProvider).go('/');
        await tester.pumpAndSettle();
        container
            .read(appRouterProvider)
            .go('/reset-password?mode=resetPassword&oobCode=${action['code']}');
        await waitFor('Request a new reset link');
        await call('/enumeration');
        await call('/finish', {'passed': true});
      } finally {
        await auth.signOut();
        await secondAuth.signOut();
        await secondApp.delete();
        client.close();
      }
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
