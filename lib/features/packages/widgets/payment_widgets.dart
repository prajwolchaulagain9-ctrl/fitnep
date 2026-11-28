import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/routes/app_routes.dart';
import '../data/package_models.dart';
import '../data/package_repository.dart';
import '../data/payment_models.dart';
import 'package_card_header.dart';

String packagePrice(num amount) =>
    'Rs. ${NumberFormat('#,##0.##').format(amount)}';

String paymentDate(DateTime date) =>
    DateFormat('d MMM yyyy, HH:mm')
        .format(date.toUtc().add(const Duration(hours: 5, minutes: 45)));

String packageErrorMessage(Object error, String fallback) =>
    error is PackageFailure ? error.message : fallback;

class PackageLoadError extends StatelessWidget {
  const PackageLoadError({required this.message, this.onRetry, super.key});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}

class PaymentReference extends StatelessWidget {
  const PaymentReference({
    required this.reference,
    required this.qrPayload,
    super.key,
  });

  final String reference;
  final String qrPayload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Test QR · non-payable',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            const Text(
              'Do not send money using this code.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Center(
              child: QrImageView(
                data: qrPayload,
                semanticsLabel: 'Non-payable test QR for reference $reference',
                size: 172,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Checkout reference',
              style: theme.textTheme.labelLarge,
              textAlign: TextAlign.center,
            ),
            SelectableText(reference, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class MembershipCard extends StatelessWidget {
  const MembershipCard({required this.member, super.key});

  final PackageMembership member;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = member.status;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PackageCardHeader(packageName: member.package.name),
            const SizedBox(height: 12),
            Chip(
              label: Text(switch (status) {
                MembershipStatus.pending => 'Pending',
                MembershipStatus.scheduled => 'Scheduled',
                MembershipStatus.active => 'Active',
                MembershipStatus.expired => 'Expired',
              }),
            ),
            const SizedBox(height: 8),
            Text(
              '${packagePrice(member.package.priceNpr)} · ${member.package.durationLabel}',
            ),
            const SizedBox(height: 8),
            if (status == MembershipStatus.pending) ...[
              const Text(
                'Your selection is saved. Your program starts after payment is verified.',
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => context.pushNamed(
                  AppRoutes.clientCheckoutName,
                  pathParameters: {'membershipId': member.id},
                ),
                child: const Text('Open checkout'),
              ),
            ] else ...[
              Text('Starts: ${paymentDate(member.startAt!)}'),
              Text('Ends: ${paymentDate(member.endAt!)}'),
              const SizedBox(height: 8),
              Text(switch (status) {
                MembershipStatus.active =>
                  '${member.daysRemaining} days remaining',
                MembershipStatus.scheduled => 'Payment verified. This package starts after your earlier paid packages end.',
                _ => 'This package has ended.',
              }, style: theme.textTheme.titleMedium),
            ],
            const SizedBox(height: 12),
            Text(member.package.features.join('\n')),
          ],
        ),
      ),
    );
  }
}

class PaymentListTile extends StatelessWidget {
  const PaymentListTile({
    required this.payment,
    this.review = false,
    super.key,
  });

  final PackagePayment payment;
  final bool review;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.receipt_long_outlined),
      title: Text(payment.package.name),
      subtitle: Text(
        [
          if (review) payment.clientName,
          '${packagePrice(payment.amountNpr)} · ${payment.status.label}',
          review ? payment.reference : paymentDate(payment.createdAt),
          if (!review && payment.rejectionReason != null)
            payment.rejectionReason!,
        ].join('\n'),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.pushNamed(
        AppRoutes.paymentDetailsName,
        pathParameters: {'id': payment.id},
      ),
    ),
  );
}
