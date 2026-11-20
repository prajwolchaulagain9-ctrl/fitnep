import 'package:fitnep/features/admin/data/models/package_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps the package API schema without losing numeric values', () {
    final package = PackageModel.fromJson({
      'id': 'package-1',
      'name': 'Premium Fitness',
      'duration_months': 3,
      'price': 2500,
      'feature_description': 'Personal training and nutrition guidance.',
      'created_at': '2026-11-19T12:00:00.000Z',
    });

    expect(package.id, 'package-1');
    expect(package.name, 'Premium Fitness');
    expect(package.durationMonths, 3);
    expect(package.price, 2500.0);
    expect(
      package.featureDescription,
      'Personal training and nutrition guidance.',
    );
    expect(package.createdAt, DateTime.utc(2026, 11, 19, 12));
  });

  test('rejects incomplete or invalid package data', () {
    expect(
      () => PackageModel.fromJson({
        'id': 'package-1',
        'name': 'Premium Fitness',
        'duration_months': 0,
        'price': -1,
        'feature_description': '',
        'created_at': 'not-a-date',
      }),
      throwsFormatException,
    );
  });
}
