import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitnep/app/theme/app_theme.dart';
import 'package:fitnep/app/routes/app_routes.dart';
import 'package:fitnep/features/packages/data/package_repository.dart';
import 'package:fitnep/features/packages/data/package_models.dart';
import 'package:fitnep/features/packages/pages/packages_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const basic = PackageOption(
  id: 'basic',
  name: 'Basic',
  durationDays: 30,
  priceNpr: 2500,
  features: ['Personalized nutrition plan', 'Weekly check-ins'],
);
const pending = PackageMembership(
  id: 'membership-a',
  package: basic,
  status: MembershipStatus.pending,
  daysRemaining: 0,
);

class _User extends Fake implements User {
  _User(this.uid);
  @override
  final String uid;
}

class _Repository extends Fake implements PackageRepository {
  List<PackageOption> items = [basic];
  List<PackageMembership> members = [];
  PackageFailure? catalogError;
  PackageFailure? membershipError;
  PackageFailure? selectionError;
  Completer<void>? selecting;
  final requests = <String>[];
  @override
  Future<List<PackageOption>> catalog() async {
    if (catalogError != null) throw catalogError!;
    return items;
  }

  @override
  Future<List<PackageMembership>> memberships() async {
    if (membershipError != null) throw membershipError!;
    return members;
  }

  @override
  Future<PackageMembership> select(
    String packageId,
    String requestId, {
    String? clientId,
  }) async {
    expect(clientId, 'client-a');
    requests.add(requestId);
    if (selecting != null) await selecting!.future;
    if (selectionError != null) throw selectionError!;
    members = [pending];
    return pending;
  }
}

Future<void> _open(
  WidgetTester tester,
  _Repository repository, {
  Stream<User?>? accounts,
  ThemeData? theme,
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const PackagesPage()),
      GoRoute(
        path: AppRoutes.clientCheckout,
        name: AppRoutes.clientCheckoutName,
        builder: (context, state) => Scaffold(
          body: Text('Checkout ${state.pathParameters['membershipId']}'),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        packageAccountProvider.overrideWith(
          (ref) => accounts ?? Stream.value(_User('client-a')),
        ),
        packageRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp.router(
        theme: theme ?? AppTheme.light,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Choose Basic'));
  await tester.tap(find.text('Choose Basic'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Confirm selection'));
  await tester.pump();
}

void main() {
  testWidgets('each package keeps its tier icon', (tester) async {
    const tiers = {
      'Basic': Icons.spa_outlined,
      'Standard': Icons.insights_rounded,
      'Premium': Icons.diamond_outlined,
      'Elite Plus': Icons.emoji_events_outlined,
      'Custom': Icons.inventory_2_outlined,
    };
    tester.view.physicalSize = const Size(430, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _open(
      tester,
      _Repository()
        ..items = [
          for (final name in tiers.keys)
            PackageOption(
              id: name,
              name: name,
              durationDays: 30,
              priceNpr: 2500,
              features: const ['Nutrition support'],
            ),
        ],
      theme: AppTheme.dark,
    );

    for (final entry in tiers.entries) {
      final card = find.ancestor(
        of: find.text(entry.key),
        matching: find.byType(Card),
      );
      expect(
        find.descendant(of: card, matching: find.byIcon(entry.value)),
        findsOneWidget,
      );
    }
  });

  testWidgets(
    'catalog fields, confirmation and repeated taps result in a saved Pending membership',
    (tester) async {
      final repository = _Repository()..selecting = Completer<void>();
      await _open(tester, repository);
      expect(find.text('Rs. 2,500'), findsOneWidget);
      expect(find.text('30 days of support'), findsOneWidget);
      expect(find.text('Weekly check-ins'), findsOneWidget);
      await tester.ensureVisible(find.text('Choose Basic'));
      await tester.tap(find.text('Choose Basic'));
      await tester.tap(find.text('Choose Basic'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Confirm selection'), findsOneWidget);
      expect(repository.requests, isEmpty);
      await tester.tap(find.text('Confirm selection'));
      await tester.pump();
      expect(repository.requests, hasLength(1));
      repository.selecting!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Checkout membership-a'), findsOneWidget);
      GoRouter.of(tester.element(find.text('Checkout membership-a'))).pop();
      await tester.pumpAndSettle();
      expect(find.text('Pending'), findsOneWidget);
      expect(
        find.text(
          'Your selection is saved. Your program starts after payment is verified.',
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Awaiting payment verification'));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(
                FilledButton,
                'Awaiting payment verification',
              ),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('selection failure preserves the request ID for a safe retry', (
    tester,
  ) async {
    final repository = _Repository()
      ..selectionError = const PackageFailure(
        'Connection lost. Retry your selection.',
      );
    await _open(tester, repository);
    await choose(tester);
    await tester.pumpAndSettle();
    expect(find.text('Connection lost. Retry your selection.'), findsOneWidget);
    repository.selectionError = null;
    await choose(tester);
    await tester.pumpAndSettle();
    expect(repository.requests, hasLength(2));
    expect(repository.requests[0], repository.requests[1]);
    expect(find.text('Checkout membership-a'), findsOneWidget);
  });

  testWidgets(
    'Active dates use Nepal time and server days remaining on a compact display',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final repository = _Repository()
        ..members = [
          PackageMembership(
            id: 'active-a',
            package: basic,
            status: MembershipStatus.active,
            daysRemaining: 7,
            startAt: DateTime.parse('2026-11-19T06:00:00Z'),
            endAt: DateTime.parse('2026-12-19T06:00:00Z'),
          ),
        ];
      await _open(tester, repository);
      expect(find.text('Starts: 19 Nov 2026, 11:45'), findsOneWidget);
      expect(find.text('Ends: 19 Dec 2026, 11:45'), findsOneWidget);
      expect(find.text('7 days remaining'), findsOneWidget);
      expect(find.textContaining('full listed price'), findsOneWidget);
      await tester.ensureVisible(find.text('Choose Basic'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed membership reads block selection; catalog errors and empty state remain retryable',
    (tester) async {
      final repository = _Repository()
        ..membershipError = const PackageFailure(
          'Membership could not be loaded.',
        );
      await _open(tester, repository);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Choose Basic'),
            )
            .onPressed,
        isNull,
      );
      repository.membershipError = null;
      repository.catalogError = const PackageFailure('Catalog offline.');
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PackagesPage)),
      );
      container.invalidate(availablePackagesProvider);
      await tester.pumpAndSettle();
      expect(find.text('Catalog offline.'), findsOneWidget);
      repository.catalogError = null;
      repository.items = [];
      await tester.ensureVisible(find.text('Try again'));
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'No packages are available right now. Please check back soon.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'sign-out hides cached membership and ignores an old in-flight selection',
    (tester) async {
      final accounts = StreamController<User?>();
      addTearDown(accounts.close);
      final repository = _Repository()..selecting = Completer<void>();
      accounts.add(_User('client-a'));
      await _open(tester, repository, accounts: accounts.stream);
      await choose(tester);
      accounts.add(null);
      await tester.pumpAndSettle();
      repository.selecting!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Pending'), findsNothing);
      expect(
        find.text('Sign in to view available packages and your membership.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
