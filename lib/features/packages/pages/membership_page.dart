import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes/app_routes.dart';
import '../../../shared/widgets/app_page.dart';
import '../data/package_models.dart';
import '../data/package_repository.dart';
import '../widgets/payment_widgets.dart';

class MembershipPage extends ConsumerWidget {
  const MembershipPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberships = ref.watch(packageMembershipsProvider);
    final payments = ref.watch(paymentHistoryProvider);
    final theme = Theme.of(context);
    return AppPage(
      title: 'My Membership',
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Your packages', style: theme.textTheme.titleLarge),
              ),
              IconButton(
                tooltip: 'Refresh membership and payments',
                onPressed: () {
                  ref.invalidate(packageMembershipsProvider);
                  ref.invalidate(paymentHistoryProvider);
                  ref.invalidate(paymentCheckoutProvider);
                },
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          memberships.when(
            skipLoadingOnRefresh: false,
            loading: () => const LinearProgressIndicator(),
            error: (error, stack) => PackageLoadError(
              message: packageErrorMessage(
                error,
                'We couldn’t load your membership.',
              ),
              onRetry: () => ref.invalidate(packageMembershipsProvider),
            ),
            data: (items) {
              final pending = items.any(
                (item) => item.status == MembershipStatus.pending,
              );
              final current = items.any(
                (item) =>
                    item.status == MembershipStatus.active ||
                    item.status == MembershipStatus.scheduled,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (items.isEmpty) const Text('No membership yet.'),
                  for (final item in items) ...[
                    MembershipCard(member: item),
                    const SizedBox(height: 8),
                  ],
                  if (!pending)
                    FilledButton(
                      onPressed: () => context.push(AppRoutes.clientPackages),
                      child: Text(
                        current ? 'Choose another package' : 'View packages',
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          Text('Payment history', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          payments.when(
            skipLoadingOnRefresh: false,
            loading: () => const LinearProgressIndicator(),
            error: (error, stack) => PackageLoadError(
              message: packageErrorMessage(
                error,
                'We couldn’t load your payment history.',
              ),
              onRetry: () => ref.invalidate(paymentHistoryProvider),
            ),
            data: (items) => items.isEmpty
                ? const Text('No payment proofs have been submitted.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final item in items) PaymentListTile(payment: item),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
