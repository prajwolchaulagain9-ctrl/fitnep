import 'package:fitnep/features/purchases/domain/entities/package_purchase_entity.dart';
import 'package:fitnep/features/packages/domain/package_models.dart';
import 'package:fitnep/features/purchases/domain/repositories/package_purchase_repository.dart';
import 'package:fitnep/features/purchases/presentation/controllers/membership_controller.dart';
import 'package:fitnep/features/purchases/presentation/pages/membership_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows historical terms from the purchase record', (
    tester,
  ) async {
    final purchase = PackagePurchaseEntity(
      id: 'purchase-1',
      packageId: 'premium',
      packageName: 'Premium',
      pricePaid: 5000,
      durationMonths: 3,
      featureDescription: 'Diet Plan, Workout Plan, Weekly Consultation',
      purchasedAt: DateTime.utc(2026, 1, 31, 12),
      expiresAt: DateTime.utc(2026, 4, 30, 12),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          packagePurchaseRepositoryProvider.overrideWithValue(
            _FakePurchaseRepository(purchase),
          ),
        ],
        child: const MaterialApp(home: MembershipPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Premium'), findsOneWidget);
    expect(find.text('NPR 5,000'), findsOneWidget);
    expect(find.text('3 months'), findsOneWidget);
    expect(
      find.text('Diet Plan, Workout Plan, Weekly Consultation'),
      findsOneWidget,
    );
    expect(find.text('31 Jan 2026'), findsOneWidget);
    expect(find.text('30 Apr 2026'), findsOneWidget);
  });

  testWidgets(
    'Pending selection explains verification and hides Active dates',
    (tester) async {
      const pending = PackagePurchaseEntity(
        id: 'pending-1',
        packageId: 'premium',
        packageName: 'Premium',
        pricePaid: 2500,
        durationMonths: 1,
        featureDescription: 'Nutrition support',
        purchasedAt: null,
        expiresAt: null,
        status: MembershipStatus.pending,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            packagePurchaseRepositoryProvider.overrideWithValue(
              _FakePurchaseRepository(pending),
            ),
          ],
          child: const MaterialApp(home: MembershipPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pending'), findsOneWidget);
      expect(
        find.byKey(const Key('membership_pending_message')),
        findsOneWidget,
      );
      expect(find.text('Active'), findsNothing);
      expect(find.byKey(const Key('membership_purchase_date')), findsNothing);
      expect(find.byKey(const Key('membership_expiry_date')), findsNothing);
    },
  );
}

class _FakePurchaseRepository implements PackagePurchaseRepository {
  final PackagePurchaseEntity purchase;

  const _FakePurchaseRepository(this.purchase);

  @override
  Future<PackagePurchaseEntity?> getCurrentPurchase() async => purchase;

  @override
  Future<PackagePurchaseEntity> purchasePackage({
    required String packageId,
    required String requestId,
  }) async => purchase;
}
