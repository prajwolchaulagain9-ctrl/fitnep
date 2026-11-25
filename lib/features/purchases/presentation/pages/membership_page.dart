import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes/app_routes.dart';
import '../controllers/membership_controller.dart';

class MembershipPage extends ConsumerWidget {
  const MembershipPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(membershipControllerProvider);
    final controller = ref.read(membershipControllerProvider.notifier);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('My Membership'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: state.isLoading ? null : controller.refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: _MembershipBody(state: state),
      ),
    );
  }
}

class _MembershipBody extends StatelessWidget {
  final MembershipState state;

  const _MembershipBody({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.isLoading && state.purchase == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 220),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (state.errorMessage != null && state.purchase == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 120),
          const Icon(Icons.cloud_off_rounded, size: 54),
          const SizedBox(height: 16),
          Text(state.errorMessage!, textAlign: TextAlign.center),
        ],
      );
    }
    final purchase = state.purchase;
    if (purchase == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 90),
          const Icon(Icons.card_membership_rounded, size: 62),
          const SizedBox(height: 16),
          Text(
            'No membership yet',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose a package to start your FitNep membership.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => context.push(AppRoutes.clientPackages),
            child: const Text('View Packages'),
          ),
        ],
      );
    }

    final currency = NumberFormat.currency(
      locale: 'en_NP',
      symbol: 'NPR ',
      decimalDigits: purchase.pricePaid % 1 == 0 ? 0 : 2,
    );
    final date = DateFormat('d MMM y');
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.card_membership_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        purchase.packageName,
                        key: const Key('membership_package_name'),
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      purchase.statusLabel,
                      style: TextStyle(
                        color: purchase.isExpired
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _TermRow(
                  label: purchase.isPending ? 'Selected price' : 'Price paid',
                  value: currency.format(purchase.pricePaid),
                  valueKey: const Key('membership_price_paid'),
                ),
                _TermRow(
                  label: purchase.isPending
                      ? 'Selected duration'
                      : 'Purchased duration',
                  value: purchase.durationDays == null
                      ? '${purchase.durationMonths} ${purchase.durationMonths == 1 ? 'month' : 'months'}'
                      : '${purchase.durationDays} days',
                  valueKey: const Key('membership_duration'),
                ),
                if (purchase.isPending)
                  const Text(
                    'Your selection is saved. Your membership starts after payment is verified.',
                    key: Key('membership_pending_message'),
                  )
                else ...[
                  _TermRow(
                    label: 'Purchase date',
                    value: date.format(purchase.purchasedAt!.toLocal()),
                    valueKey: const Key('membership_purchase_date'),
                  ),
                  _TermRow(
                    label: 'Expiry date',
                    value: date.format(purchase.expiresAt!.toLocal()),
                    valueKey: const Key('membership_expiry_date'),
                  ),
                  if (purchase.daysRemaining != null)
                    Text('${purchase.daysRemaining} days remaining'),
                ],
                const Divider(height: 32),
                Text(
                  'Included features',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  purchase.featureDescription,
                  key: const Key('membership_features'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TermRow extends StatelessWidget {
  final String label;
  final String value;
  final Key valueKey;

  const _TermRow({
    required this.label,
    required this.value,
    required this.valueKey,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              key: valueKey,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
