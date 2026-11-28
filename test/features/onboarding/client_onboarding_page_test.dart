import 'package:fitnep/app/routes/app_routes.dart';
import 'package:fitnep/app/theme/app_theme.dart';
import 'package:fitnep/features/authorization/data/account.dart';
import 'package:fitnep/features/authorization/data/authorization_repository.dart';
import 'package:fitnep/features/onboarding/data/client_onboarding_status.dart';
import 'package:fitnep/features/onboarding/pages/client_onboarding_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('validates height and weight and saves before opening packages', (
    tester,
  ) async {
    final profile = _ProfileApi();
    await _open(tester, profile);
    expect(find.text('Step 1 of 3'), findsOneWidget);
    await _tap(tester, 'Get started');

    expect(find.byType(TextFormField), findsNWidgets(2));
    await tester.enterText(find.byKey(const ValueKey('height_cm')), '10');
    await tester.enterText(find.byKey(const ValueKey('weight_kg')), '70');
    await _tap(tester, 'Review setup');
    expect(find.text('Enter a value from 30 to 300.'), findsOneWidget);
    expect(profile.writes, isEmpty);

    await tester.enterText(find.byKey(const ValueKey('height_cm')), '175');
    await tester.pump();
    expect(find.text('22.9 kg/m²'), findsOneWidget);
    await _tap(tester, 'Review setup');
    expect(find.text('Step 3 of 3'), findsOneWidget);
    expect(find.text('Package selection'), findsNothing);
    expect(profile.writes.single, {
      'expected_client_id': 'client-1',
      'status': 'draft',
      'heightCm': 175,
      'weightKg': 70,
    });

    profile.failNext = true;
    await _tap(tester, 'Explore packages');
    expect(find.text('Try saving again.'), findsOneWidget);
    expect(find.text('22.9 kg/m²'), findsOneWidget);
    expect(find.text('Package selection'), findsNothing);
    await _tap(tester, 'Explore packages');
    expect(find.text('Package selection'), findsOneWidget);
    expect(profile.saved['status'], 'completed');
  });

  testWidgets('skips with partial input and resumes on a later visit', (
    tester,
  ) async {
    final profile = _ProfileApi();
    await _open(tester, profile);
    await _tap(tester, 'Get started');
    await tester.enterText(find.byKey(const ValueKey('height_cm')), '165.5');
    await tester.enterText(find.byKey(const ValueKey('weight_kg')), '0');
    await _tap(tester, 'Skip for now');
    expect(find.text('Package selection'), findsOneWidget);
    expect(profile.saved, {'status': 'skipped', 'heightCm': 165.5});

    await _tap(tester, 'Resume setup');
    expect(find.text('Step 2 of 3'), findsOneWidget);
    expect(find.text('165.5'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('weight_kg')), '65');
    await _tap(tester, 'Review setup');
    expect(profile.saved['status'], 'skipped');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await _tap(tester, 'Resume setup');
    final weight = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('weight_kg')),
        matching: find.byType(EditableText),
      ),
    );
    expect(double.tryParse(weight.controller.text), 65);
    await _tap(tester, 'Review setup');
    await _tap(tester, 'Finish setup');
    expect(find.text('Package selection'), findsOneWidget);
    expect(profile.saved['status'], 'completed');
  });
}

Future<void> _open(WidgetTester tester, _ProfileApi profile) async {
  tester.view.physicalSize = const Size(375, 680);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: AppRoutes.clientOnboarding,
    routes: [
      GoRoute(
        path: AppRoutes.clientOnboarding,
        builder: (_, _) => const ClientOnboardingPage(clientId: 'client-1'),
      ),
      GoRoute(
        path: AppRoutes.clientPackages,
        builder: (context, _) => Consumer(
          builder: (context, ref, _) => Scaffold(
            appBar: AppBar(title: const Text('Package selection')),
            body:
                ref.watch(clientOnboardingStatusProvider('client-1')).value ==
                    ClientOnboardingStatus.skipped
                ? TextButton(
                    onPressed: () => context.push(AppRoutes.clientOnboarding),
                    child: const Text('Resume setup'),
                  )
                : null,
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authorizationRepositoryProvider.overrideWithValue(profile)],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String label) async {
  final button = find.text(label);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

class _ProfileApi extends Fake implements AuthorizationRepository {
  final saved = <String, dynamic>{'status': 'required'};
  final writes = <Map<String, dynamic>>[];
  bool failNext = false;

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? data,
    Map<String, dynamic>? query,
  }) async {
    if (method == 'GET') {
      expect(path, 'profile/me');
    } else {
      expect(path, 'profile/me/onboarding');
      expect(method, 'PUT');
      writes.add(data!);
      if (failNext) {
        failNext = false;
        throw const AuthorizationFailure('Try saving again.');
      }
      saved.addAll({...data}..remove('expected_client_id'));
    }
    return {
      'account': {'id': 'client-1'},
      'onboarding': {...saved},
    };
  }
}
