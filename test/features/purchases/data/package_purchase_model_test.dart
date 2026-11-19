import 'package:fitnep/features/purchases/data/models/package_purchase_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses every immutable purchased term', () {
    final purchase = PackagePurchaseModel.fromJson({
      'id': 'purchase-1',
      'package_id': 'premium',
      'package_name': 'Premium',
      'price_paid': 5000,
      'duration_months': 3,
      'feature_description': 'Diet Plan, Workout Plan, Weekly Consultation',
      'purchased_at': '2026-01-31T12:00:00.000Z',
      'expires_at': '2026-04-30T12:00:00.000Z',
    });

    expect(purchase.packageName, 'Premium');
    expect(purchase.pricePaid, 5000);
    expect(purchase.durationMonths, 3);
    expect(
      purchase.featureDescription,
      'Diet Plan, Workout Plan, Weekly Consultation',
    );
    expect(purchase.purchasedAt, DateTime.utc(2026, 1, 31, 12));
    expect(purchase.expiresAt, DateTime.utc(2026, 4, 30, 12));
  });
}
