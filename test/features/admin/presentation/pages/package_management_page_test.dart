import 'dart:async';

import 'package:fitnep/app/routes/app_routes.dart';
import 'package:fitnep/features/admin/domain/entities/package_entity.dart';
import 'package:fitnep/features/admin/domain/entities/package_history_entity.dart';
import 'package:fitnep/features/admin/domain/repositories/package_repository.dart';
import 'package:fitnep/features/admin/presentation/controllers/package_management_controller.dart';
import 'package:fitnep/features/admin/presentation/pages/create_package_page.dart';
import 'package:fitnep/features/admin/presentation/pages/package_management_page.dart';
import 'package:fitnep/features/admin/presentation/pages/package_history_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('validates every required package field before saving', (
    tester,
  ) async {
    final repository = _FakePackageRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [packageRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: CreatePackagePage()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('create_package_submit')));
    await tester.pump();

    expect(find.text('Package name is required.'), findsOneWidget);
    expect(
      find.text('Enter a positive whole number of months.'),
      findsOneWidget,
    );
    expect(find.text('Enter a valid positive price.'), findsOneWidget);
    expect(find.text('Feature description is required.'), findsOneWidget);
    expect(repository.createCalls, 0);
  });

  testWidgets(
    'saves once, refreshes, and shows the created package in the list',
    (tester) async {
      final repository = _FakePackageRepository(delayCreate: true);
      final router = GoRouter(
        initialLocation: AppRoutes.adminPackages,
        routes: [
          GoRoute(
            path: AppRoutes.adminPackages,
            builder: (_, _) => const PackageManagementPage(),
            routes: [
              GoRoute(
                path: 'create',
                builder: (_, _) => const CreatePackagePage(),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [packageRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create package'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('package_name_field')),
        'Premium Fitness',
      );
      await tester.enterText(
        find.byKey(const Key('package_duration_field')),
        '3',
      );
      await tester.enterText(
        find.byKey(const Key('package_price_field')),
        '2500',
      );
      await tester.enterText(
        find.byKey(const Key('package_feature_field')),
        'Personal training and nutrition guidance.',
      );

      await tester.tap(find.byKey(const Key('create_package_submit')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('create_package_submit')));
      await tester.pump();

      expect(repository.createCalls, 1);
      expect(find.text('Saving package...'), findsOneWidget);

      repository.completeCreate();
      await tester.pumpAndSettle();

      expect(find.text('Package Management'), findsOneWidget);
      expect(find.text('Premium Fitness'), findsOneWidget);
      expect(find.text('3 months'), findsOneWidget);
      expect(
        find.text('Personal training and nutrition guidance.'),
        findsOneWidget,
      );
      expect(repository.getCalls, greaterThanOrEqualTo(2));
    },
  );

  testWidgets('opens package history with actor, time, and changed values', (
    tester,
  ) async {
    final repository = _FakePackageRepository();
    final router = GoRouter(
      initialLocation: AppRoutes.adminPackages,
      routes: [
        GoRoute(
          path: AppRoutes.adminPackages,
          builder: (_, _) => const PackageManagementPage(),
          routes: [
            GoRoute(
              path: 'history',
              builder: (_, _) => const PackageHistoryPage(),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [packageRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('package_history_button')));
    await tester.pumpAndSettle();

    expect(find.text('Package History'), findsOneWidget);
    expect(find.text('Package updated'), findsOneWidget);
    expect(find.text('Premium Fitness'), findsOneWidget);
    expect(find.text('By FitNep CEO'), findsOneWidget);
    expect(find.text('NPR 5,000'), findsOneWidget);
    expect(find.text('NPR 6,500'), findsOneWidget);
  });
}

class _FakePackageRepository implements PackageRepository {
  final bool delayCreate;
  final List<PackageEntity> _packages = [];
  Completer<PackageEntity>? _createCompleter;
  PackageEntity? _pendingPackage;
  int getCalls = 0;
  int createCalls = 0;

  _FakePackageRepository({this.delayCreate = false});

  @override
  Future<List<PackageEntity>> getPackages() async {
    getCalls++;
    return List<PackageEntity>.unmodifiable(_packages);
  }

  @override
  Future<List<PackageEntity>> getActivePackages() => getPackages();

  @override
  Future<List<PackageHistoryEntity>> getPackageHistory() async {
    return [
      PackageHistoryEntity(
        id: 'history-1',
        packageId: 'premium',
        packageName: 'Premium Fitness',
        adminId: 'admin-1',
        adminName: 'FitNep CEO',
        action: PackageHistoryAction.updated,
        previousValues: const {'price': 5000},
        newValues: const {'price': 6500},
        changedAt: DateTime.utc(2026, 11, 20, 4, 15),
      ),
    ];
  }

  @override
  Future<PackageEntity> createPackage({
    required String requestId,
    required String name,
    required int durationMonths,
    required double price,
    required String featureDescription,
  }) {
    createCalls++;
    final package = PackageEntity(
      id: requestId,
      name: name,
      durationMonths: durationMonths,
      price: price,
      featureDescription: featureDescription,
      isActive: true,
      createdAt: DateTime.utc(2026, 11, 19, 12),
    );
    if (!delayCreate) {
      _packages.add(package);
      return Future.value(package);
    }
    _pendingPackage = package;
    _createCompleter = Completer<PackageEntity>();
    return _createCompleter!.future;
  }

  @override
  Future<PackageEntity> updatePackage({
    required String id,
    required String name,
    required int durationMonths,
    required double price,
    required String featureDescription,
  }) async {
    final index = _packages.indexWhere((package) => package.id == id);
    final updated = _packages[index].copyWith(
      name: name,
      durationMonths: durationMonths,
      price: price,
      featureDescription: featureDescription,
    );
    _packages[index] = updated;
    return updated;
  }

  @override
  Future<PackageEntity> setPackageActiveStatus({
    required String id,
    required bool isActive,
  }) async {
    final index = _packages.indexWhere((package) => package.id == id);
    final updated = _packages[index].copyWith(isActive: isActive);
    _packages[index] = updated;
    return updated;
  }

  void completeCreate() {
    final package = _pendingPackage!;
    _packages.add(package);
    _createCompleter!.complete(package);
  }
}
