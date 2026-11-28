import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes/app_routes.dart';
import '../../../shared/widgets/app_page.dart';
import '../data/package_repository.dart';
import '../data/package_models.dart';
import '../widgets/package_card_header.dart';
import '../widgets/payment_widgets.dart';

class PackagesPage extends ConsumerWidget {
  const PackagesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(packageAccountProvider)
      .when(
        skipLoadingOnRefresh: false,
        data: (user) => user == null
            ? const AppPage(
                title: 'Packages',
                child: Text(
                  'Sign in to view available packages and your membership.',
                ),
              )
            : _PackageContent(clientId: user.uid, key: ValueKey(user.uid)),
        loading: () => const AppPage(
          title: 'Packages',
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, stack) => AppPage(
          title: 'Packages',
          child: PackageLoadError(
            message: packageErrorMessage(
              error,
              'We couldn’t load your packages.',
            ),
            onRetry: () => ref.invalidate(packageAccountProvider),
          ),
        ),
      );
}

class _PackageContent extends ConsumerStatefulWidget {
  const _PackageContent({required this.clientId, super.key});
  final String clientId;
  @override
  ConsumerState<_PackageContent> createState() => _PackageContentState();
}

class _PackageContentState extends ConsumerState<_PackageContent> {
  String? _busyId;
  String? _requestPackageId;
  String? _requestId;
  String? _error;

  Future<void> _select(PackageOption item, {required bool isUpgrade}) async {
    if (_busyId != null) return;
    setState(() => _busyId = item.id);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Choose ${item.name}?'),
        content: Text(
          '${packagePrice(item.priceNpr)} for ${item.durationLabel}. '
          '${isUpgrade ? 'You’re selecting a new package at its full price. Once verified, it starts after your current paid packages end.' : 'Your package stays pending until your payment proof is verified.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm selection'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true ||
        ref.read(packageAccountProvider).asData?.value?.uid !=
            widget.clientId) {
      setState(() => _busyId = null);
      return;
    }
    if (_requestPackageId != item.id) {
      _requestPackageId = item.id;
      _requestId = newPackageRequestId();
    }
    setState(() => _error = null);
    try {
      final membership = await ref
          .read(packageRepositoryProvider)
          .select(item.id, _requestId!, clientId: widget.clientId);
      if (!mounted) return;
      _requestId = null;
      _requestPackageId = null;
      ref.invalidate(packageMembershipsProvider);
      ref.invalidate(paymentCheckoutProvider);
      context.pushNamed(
        AppRoutes.clientCheckoutName,
        pathParameters: {'membershipId': membership.id},
      );
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = packageErrorMessage(
          error,
          'We couldn’t save your selection. Please try again.',
        ),
      );
      ref.invalidate(availablePackagesProvider);
      ref.invalidate(packageMembershipsProvider);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catalog = ref.watch(availablePackagesProvider);
    final memberships = ref.watch(packageMembershipsProvider);
    final records = memberships.value ?? const <PackageMembership>[];
    final hasPending = records.any(
      (item) => item.status == MembershipStatus.pending,
    );
    final hasPaid = records.any(
      (item) =>
          item.status == MembershipStatus.active ||
          item.status == MembershipStatus.scheduled,
    );
    return AppPage(
      title: 'Packages',
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasPending || hasPaid) ...[
            Text('Your membership', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final member in records.where(
              (member) => member.status != MembershipStatus.expired,
            ))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: MembershipCard(member: member),
              ),
          ],
          OutlinedButton.icon(
            onPressed: () => context.push(AppRoutes.clientMembership),
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('Membership and payment history'),
          ),
          if (memberships.isLoading) const LinearProgressIndicator(),
          if (memberships.hasError)
            PackageLoadError(
              message: packageErrorMessage(
                memberships.error!,
                'We couldn’t load your membership.',
              ),
              onRetry: () => ref.invalidate(packageMembershipsProvider),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Available packages',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Refresh packages and membership',
                onPressed: _busyId == null
                    ? () {
                        ref.invalidate(availablePackagesProvider);
                        ref.invalidate(packageMembershipsProvider);
                        ref.invalidate(paymentCheckoutProvider);
                      }
                    : null,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (hasPending)
            const Text(
              'Finish checkout and wait for verification before choosing another package.',
            )
          else if (hasPaid)
            const Text(
              'A new package costs its full listed price. Once verified, it starts after your current paid packages end.',
            ),
          if (_error != null) PackageLoadError(message: _error!),
          catalog.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (error, stack) => PackageLoadError(
              message: packageErrorMessage(
                error,
                'We couldn’t load available packages.',
              ),
              onRetry: () => ref.invalidate(availablePackagesProvider),
            ),
            data: (items) => items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No packages are available right now. Please check back soon.',
                    ),
                  )
                : Column(
                    children: [
                      for (final item in items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  PackageCardHeader(packageName: item.name),
                                  const SizedBox(height: 12),
                                  Text(
                                    packagePrice(item.priceNpr),
                                    style: theme.textTheme.headlineMedium,
                                  ),
                                  Text(
                                    '${item.durationLabel} of support',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 16),
                                  for (final feature in item.features)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            Icons.check_circle_outline,
                                            size: 20,
                                            color: theme.colorScheme.primary,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(child: Text(feature)),
                                        ],
                                      ),
                                    ),
                                  const SizedBox(height: 12),
                                  FilledButton(
                                    key: Key('select_package_${item.id}'),
                                    onPressed:
                                        _busyId != null ||
                                            hasPending ||
                                            memberships.isLoading ||
                                            !memberships.hasValue ||
                                            memberships.hasError
                                        ? null
                                        : () =>
                                              _select(item, isUpgrade: hasPaid),
                                    child: Text(
                                      _busyId == item.id
                                          ? 'Selecting…'
                                          : hasPending
                                          ? 'Awaiting payment verification'
                                          : 'Choose ${item.name}',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
