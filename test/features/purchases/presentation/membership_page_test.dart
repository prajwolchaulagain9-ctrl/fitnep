import 'package:fitnep/features/packages/data/package_models.dart';
import 'package:fitnep/features/packages/data/package_repository.dart';
import 'package:fitnep/features/packages/data/payment_models.dart';
import 'package:fitnep/features/packages/pages/membership_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const package = PackageOption(
  id: 'premium',
  name: 'Premium',
  priceNpr: 5000,
  durationDays: 90,
  durationMonths: 3,
  features: ['Diet Plan, Workout Plan, Weekly Consultation'],
);

Future<void> openMembership(
  WidgetTester tester,
  PackageMembership membership, {
  List<PackagePayment> payments = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        packageMembershipsProvider.overrideWith((ref) async => [membership]),
        paymentHistoryProvider.overrideWith((ref) async => payments),
      ],
      child: const MaterialApp(home: MembershipPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows saved terms and dates for a verified scheduled package', (
    tester,
  ) async {
    await openMembership(
      tester,
      PackageMembership(
        id: 'scheduled-1',
        package: package,
        status: MembershipStatus.scheduled,
        daysRemaining: 0,
        startAt: DateTime.utc(2026, 1, 31, 12),
        endAt: DateTime.utc(2026, 4, 30, 12),
      ),
    );

    expect(find.text('Premium'), findsOneWidget);
    expect(find.text('Rs. 5,000 · 3 months'), findsOneWidget);
    expect(
      find.text('Diet Plan, Workout Plan, Weekly Consultation'),
      findsOneWidget,
    );
    expect(find.text('Starts: 31 Jan 2026, 17:45'), findsOneWidget);
    expect(find.text('Ends: 30 Apr 2026, 17:45'), findsOneWidget);
    expect(find.text('Scheduled'), findsOneWidget);
    expect(find.text('Choose another package'), findsOneWidget);
  });

  testWidgets('pending selection and rejected proof are visible in history', (
    tester,
  ) async {
    await openMembership(
      tester,
      const PackageMembership(
        id: 'pending-1',
        package: package,
        status: MembershipStatus.pending,
        daysRemaining: 0,
      ),
      payments: [
        PackagePayment(
          id: 'payment-1',
          membershipId: 'pending-1',
          clientName: 'Client A',
          package: package,
          amountNpr: 5000,
          status: PaymentStatus.rejected,
          reference: 'TEST-1',
          qrPayload: 'fitnep-test:TEST-1',
          createdAt: DateTime.utc(2026),
          rejectionReason: 'The screenshot was unreadable.',
        ),
      ],
    );

    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Open checkout'), findsOneWidget);
    expect(find.textContaining('Starts:'), findsNothing);
    expect(find.text('Choose another package'), findsNothing);
    expect(find.text('Payment history'), findsOneWidget);
    expect(find.textContaining('Rejected'), findsOneWidget);
    expect(
      find.textContaining('The screenshot was unreadable.'),
      findsOneWidget,
    );
  });
}
