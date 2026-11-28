import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitnep/app/routes/app_routes.dart';
import 'package:fitnep/app/routes/route_access_gate.dart';
import 'package:fitnep/app/theme/app_theme.dart';
import 'package:fitnep/features/authentication/hosted_session_gate.dart';
import 'package:fitnep/features/notifications/data/notification_destination_record.dart';
import 'package:fitnep/features/notifications/notification_destination_controller.dart';
import 'package:fitnep/features/packages/data/package_models.dart';
import 'package:fitnep/features/packages/data/package_repository.dart';
import 'package:fitnep/features/packages/data/payment_models.dart';
import 'package:fitnep/features/packages/pages/checkout_page.dart';
import 'package:fitnep/features/packages/pages/package_approvals_page.dart';
import 'package:fitnep/features/packages/pages/payment_details_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../support/offline_hosted_session.dart';

const package = PackageOption(
  id: 'basic',
  name: 'Basic',
  priceNpr: 2500,
  durationDays: 30,
  features: ['Nutrition support'],
);
final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGOor6//DwAFewJ94ITM6gAAAABJRU5ErkJggg==',
);

class _User extends Fake implements User {
  _User(this.uid);

  @override
  final String uid;
}

class _Picker extends Fake implements ImagePicker {
  Uint8List bytes = Uint8List.fromList([1, 2, 3]);
  Future<XFile?>? selection;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async => selection ?? XFile.fromData(bytes, name: 'proof.png');
}

class _Repository extends Fake implements PackageRepository {
  final decision = Completer<void>();
  final submission = Completer<void>();
  PaymentStatus status = PaymentStatus.pending;
  int decisions = 0;
  int submissions = 0;
  bool legacy = false;
  String? rejectionReason;
  final adjustments = <PaymentAdjustment>[];

  PackagePayment get record => PackagePayment(
    id: 'payment-1',
    membershipId: 'membership-1',
    clientName: 'Client A',
    package: package,
    amountNpr: 2500,
    status: status,
    reference: 'TEST-1',
    qrPayload: 'fitnep-test:TEST-1',
    createdAt: DateTime.utc(2026),
    revision: 1,
    reviewedByName: decisions > 0 ? 'Reviewer A' : null,
    rejectionReason: rejectionReason,
  );

  @override
  Future<PackageCheckout?> checkout() async => const PackageCheckout(
    membershipId: 'membership-1',
    package: package,
    amountNpr: 2500,
    reference: 'TEST-1',
    qrPayload: 'fitnep-test:TEST-1',
  );

  @override
  Future<PackagePayment> submitProof({
    required String membershipId,
    required String clientId,
    required String reference,
    required String requestId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    expect(membershipId, 'membership-1');
    expect(clientId, 'u-client');
    expect(reference, 'TEST-1');
    expect(requestId, isNotEmpty);
    expect(bytes, png);
    expect(contentType, 'image/png');
    submissions++;
    await submission.future;
    return record;
  }

  @override
  Future<List<PackagePayment>> reviewQueue(PaymentStatus status) async =>
      this.status == status ? [record] : [];

  @override
  Future<PaymentDetails?> paymentDetails(String id) async =>
      legacy ? null : (payment: record, adjustments: [...adjustments]);

  @override
  Future<void> addAdjustment({
    required String paymentId,
    required String reason,
    required num amountDeltaNpr,
    required String requestId,
  }) async {
    expect(paymentId, 'payment-1');
    expect(requestId, isNotEmpty);
    adjustments.add(
      PaymentAdjustment(
        amountDeltaNpr: amountDeltaNpr,
        reason: reason,
        createdAt: DateTime.utc(2026),
      ),
    );
  }

  @override
  Future<Uint8List> paymentProof(String id) async => png;

  @override
  Future<PackagePayment> reviewPayment(
    PackagePayment payment, {
    String? reason,
  }) async {
    expect(payment.id, 'payment-1');
    expect(payment.revision, 1);
    decisions++;
    await decision.future;
    rejectionReason = reason;
    status = reason == null ? PaymentStatus.verified : PaymentStatus.rejected;
    return record;
  }
}

Future<void> _open(
  WidgetTester tester,
  _Repository repository, {
  FitNepRole role = FitNepRole.admin,
  String initialLocation = '/',
  _Picker? picker,
  Future<String?> Function()? checkSession,
}) async {
  final uid = 'u-${role.name}';
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/', builder: (_, _) => const PackageApprovalsPage()),
      GoRoute(
        path: AppRoutes.clientCheckout,
        name: AppRoutes.clientCheckoutName,
        builder: (_, state) {
          final checkout = CheckoutPage(
            membershipId: state.pathParameters['membershipId']!,
          );
          return checkSession == null
              ? checkout
              : HostedSessionGate(uid: uid, child: checkout);
        },
      ),
      GoRoute(
        path: AppRoutes.paymentDetails,
        name: AppRoutes.paymentDetailsName,
        builder: (_, state) =>
            PaymentDetailsPage(paymentId: state.pathParameters['id']!),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (checkSession != null) ...[
          offlineHostedSessionOverride,
          hostedSessionReadyProvider.overrideWith((ref, uid) => checkSession()),
        ],
        packageAccountProvider.overrideWith((ref) => Stream.value(_User(uid))),
        packageRepositoryProvider.overrideWithValue(repository),
        notificationDestinationProvider.overrideWith(
          (ref, request) async => NotificationDestinationRecord(
            id: request.referenceId,
            title: 'Legacy receipt',
            description: null,
            fields: const [],
          ),
        ),
        routeSessionProvider.overrideWith(
          (ref) async => (
            uid: uid,
            role: role,
            auditRead: false,
            paymentsVerify: role == FitNepRole.staff,
          ),
        ),
        if (picker != null)
          paymentImagePickerProvider.overrideWithValue(picker),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: router,
        builder: checkSession == null
            ? null
            : (_, child) => HostedSessionObserver(child: child!),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openRecord(WidgetTester tester) async {
  await tester.tap(find.text('Basic'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump();
}

void main() {
  testWidgets('old payment notifications retain their receipt details', (
    tester,
  ) async {
    await _open(
      tester,
      _Repository()..legacy = true,
      role: FitNepRole.client,
      initialLocation: '/payments/legacy-id',
    );
    expect(find.text('Legacy receipt'), findsOneWidget);
    expect(find.text('Reference: legacy-id'), findsOneWidget);
  });

  testWidgets('checkout validates proof and submits without typed fields', (
    tester,
  ) async {
    final repository = _Repository();
    final picker = _Picker();
    await _open(
      tester,
      repository,
      role: FitNepRole.client,
      initialLocation: '/client/checkout/membership-1',
      picker: picker,
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Test QR · non-payable'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('TEST-1'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Submit proof for review'),
          )
          .onPressed,
      isNull,
    );
    await _tap(tester, 'Choose proof image');
    await tester.pumpAndSettle();
    expect(find.textContaining('Choose a JPEG, PNG or WebP'), findsOneWidget);
    picker.bytes = png;
    await _tap(tester, 'Choose proof image');
    await tester.pumpAndSettle();
    await _tap(tester, 'Submit proof for review');
    await _tap(tester, 'Submit proof for review');
    expect(repository.submissions, 1);
    repository.submission.complete();
    await tester.pumpAndSettle();
    expect(find.text('Payment details'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Verify payment'), findsNothing);
  });

  testWidgets('returning from the gallery keeps the selected checkout proof', (
    tester,
  ) async {
    final repository = _Repository();
    final selection = Completer<XFile?>();
    final recheck = Completer<String?>();
    var sessionChecks = 0;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _open(
      tester,
      repository,
      role: FitNepRole.client,
      initialLocation: '/client/checkout/membership-1',
      picker: _Picker()..selection = selection.future,
      checkSession: () async =>
          ++sessionChecks == 1 ? 'session-1' : recheck.future,
    );

    await _tap(tester, 'Choose proof image');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(sessionChecks, 2);
    expect(find.text('Checkout'), findsOneWidget);

    selection.complete(XFile.fromData(png, name: 'proof.png'));
    await tester.pump();
    expect(find.text('Change proof image'), findsOneWidget);

    recheck.complete('session-1');
    await tester.pumpAndSettle();
    await _tap(tester, 'Submit proof for review');
    expect(repository.submissions, 1);
    repository.submission.complete();
    await tester.pumpAndSettle();
    expect(find.text('Payment details'), findsOneWidget);
  });

  testWidgets('a rejected session hides checkout during revalidation', (
    tester,
  ) async {
    final recheck = Completer<String?>();
    var sessionChecks = 0;
    await _open(
      tester,
      _Repository(),
      role: FitNepRole.client,
      initialLocation: '/client/checkout/membership-1',
      checkSession: () async =>
          ++sessionChecks == 1 ? 'session-1' : recheck.future,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CheckoutPage)),
    );

    container.invalidate(hostedSessionReadyProvider, asReload: true);
    await tester.pump();
    await tester.pump();
    expect(sessionChecks, 2);
    expect(find.byType(CheckoutPage), findsNothing);

    recheck.completeError(StateError('Session ended.'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckoutPage), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('reviewer checks displayed proof before verifying once', (
    tester,
  ) async {
    final repository = _Repository();
    await _open(tester, repository, role: FitNepRole.staff);
    expect(find.textContaining('Client A'), findsOneWidget);
    expect(find.textContaining('TEST-1'), findsOneWidget);
    await _openRecord(tester);
    expect(find.text('Test QR · non-payable'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Verify payment'),
          )
          .onPressed,
      isNull,
    );

    final proof = tester.widget<Image>(find.byType(Image));
    final proofContext = tester.element(find.byType(Image));
    await tester.runAsync(() async => precacheImage(proof.image, proofContext));
    await tester.pumpAndSettle();
    await _tap(
      tester,
      'I checked the QR, submitted proof and selected package.',
    );
    await _tap(tester, 'Verify payment');
    await _tap(tester, 'Verify payment');
    expect(repository.decisions, 1);
    repository.decision.complete();
    await tester.pumpAndSettle();
    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('Reviewed by Reviewer A'), findsOneWidget);
    expect(find.text('Log adjustment'), findsNothing);
    GoRouter.of(tester.element(find.byType(PaymentDetailsPage))).pop();
    await tester.pumpAndSettle();
    expect(find.text('No payments are awaiting verification.'), findsOneWidget);
  });

  testWidgets('reject requires a reason and shows the saved decision', (
    tester,
  ) async {
    final repository = _Repository()..decision.complete();
    await _open(tester, repository);
    await _openRecord(tester);
    await _tap(tester, 'Reject payment');
    await tester.pumpAndSettle();
    await _tap(tester, 'Confirm rejection');
    expect(find.text('Enter a reason.'), findsOneWidget);
    expect(repository.decisions, 0);
    await tester.enterText(
      find.byType(TextFormField),
      'Upload a clear screenshot.',
    );
    await _tap(tester, 'Confirm rejection');
    await tester.pumpAndSettle();
    expect(repository.rejectionReason, 'Upload a clear screenshot.');
    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text(repository.rejectionReason!), findsOneWidget);
  });

  testWidgets(
    'administrator appends a logged adjustment to a verified payment',
    (tester) async {
      final repository = _Repository()..status = PaymentStatus.verified;
      await _open(tester, repository, initialLocation: '/payments/payment-1');
      await _tap(tester, 'Log adjustment');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount change in NPR'),
        '-125.50',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Reason'),
        'Reconcile recorded total.',
      );
      await _tap(tester, 'Save adjustment');
      await tester.pumpAndSettle();
      expect(repository.adjustments.single.amountDeltaNpr, -125.5);
      expect(repository.record.amountNpr, 2500);
      expect(find.textContaining('Reconcile recorded total.'), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);
    },
  );
}
