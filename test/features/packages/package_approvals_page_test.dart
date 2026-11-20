import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitnep/app/theme/app_theme.dart';
import 'package:fitnep/features/packages/data/package_repository.dart';
import 'package:fitnep/features/packages/domain/package_models.dart';
import 'package:fitnep/features/packages/presentation/pages/package_approvals_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const member = PackageMembership(
  id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  clientId: 'demo-client',
  package: PackageOption(
    id: 'basic',
    name: 'Basic',
    priceNpr: 2500,
    durationDays: 30,
    features: ['Nutrition support'],
  ),
  status: MembershipStatus.pending,
  daysRemaining: 0,
);

class _Admin extends Fake implements User {
  @override
  String get uid => 'admin-a';
}

class _Repository extends Fake implements PackageRepository {
  final pending = Completer<void>();
  List<PackageMembership> records = [member];
  int calls = 0;
  String? reference;
  @override
  Future<List<PackageMembership>> pendingApprovals() async => records;
  @override
  Future<PackageMembership> verifyPayment(String id, String value) async {
    calls++;
    reference = value;
    await pending.future;
    records = [];
    return PackageMembership(
      id: id,
      package: member.package,
      status: MembershipStatus.active,
      daysRemaining: 30,
      startAt: DateTime(2026, 11, 19),
      endAt: DateTime(2026, 12, 19),
    );
  }
}

void main() {
  testWidgets(
    'manual approval requires a reference, submits once and refreshes the queue',
    (tester) async {
      final repository = _Repository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            packageAccountProvider.overrideWith(
              (ref) => Stream.value(_Admin()),
            ),
            packageRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const PackageApprovalsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Review payment'));
      await tester.tap(find.text('Review payment'));
      await tester.tap(find.text('Review payment'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Verify and activate'), findsOneWidget);
      await tester.tap(find.text('Verify and activate'));
      await tester.pump();
      expect(repository.calls, 0);
      await tester.enterText(find.byType(TextFormField), 'TEST-RECEIPT-01');
      await tester.tap(find.text('Verify and activate'));
      await tester.pumpAndSettle();
      expect(repository.calls, 1);
      expect(repository.reference, 'TEST-RECEIPT-01');
      repository.pending.complete();
      await tester.pumpAndSettle();
      expect(
        find.text('No packages are awaiting verification.'),
        findsOneWidget,
      );
      expect(find.text('Payment verified. Package activated.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
