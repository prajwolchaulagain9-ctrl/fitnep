import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/widgets/app_page.dart';
import '../../data/package_repository.dart';
import '../../domain/package_models.dart';

class PackagesPage extends ConsumerWidget {
  const PackagesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(packageAccountProvider)
      .when(
        data: (user) => user == null
            ? const AppPage(
                title: 'Packages',
                child: Text(
                  'Sign in to view available packages and your membership.',
                ),
              )
            : _PackageContent(key: ValueKey(user.uid)),
        loading: () => const AppPage(
          title: 'Packages',
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, stack) => AppPage(
          title: 'Packages',
          child: _Failure(
            error: error,
            onRetry: () => ref.invalidate(packageAccountProvider),
          ),
        ),
      );
}

class _PackageContent extends ConsumerStatefulWidget {
  const _PackageContent({super.key});
  @override
  ConsumerState<_PackageContent> createState() => _PackageContentState();
}

class _PackageContentState extends ConsumerState<_PackageContent> {
  String? _busyId;
  String? _requestPackageId;
  String? _requestId;
  String? _error;
  PackageMembership? _saved;

  Future<void> _select(PackageOption item) async {
    if (_busyId != null) return;
    setState(() => _busyId = item.id);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Choose ${item.name}?'),
        content: Text(
          '${_price(item.priceNpr)} for ${item.durationDays} days. Your package will remain Pending until payment is verified.',
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
    if (confirmed != true) {
      setState(() => _busyId = null);
      return;
    }
    if (_requestPackageId != item.id) {
      _requestPackageId = item.id;
      _requestId =
          '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    }
    setState(() => _error = null);
    try {
      final membership = await ref
          .read(packageRepositoryProvider)
          .select(item.id, _requestId!);
      if (!mounted) return;
      setState(() => _saved = membership);
      ref.invalidate(packageMembershipsProvider);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error is PackageFailure
            ? error.message
            : 'We couldn’t save your selection. Please try again.',
      );
      ref.invalidate(availablePackagesProvider);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catalog = ref.watch(availablePackagesProvider);
    final memberships = ref.watch(packageMembershipsProvider);
    final records =
        memberships.value ??
        (_saved == null ? <PackageMembership>[] : [_saved!]);
    final hasPending = records.any(
      (item) => item.status == MembershipStatus.pending,
    );
    return AppPage(
      title: 'Packages',
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Your next step starts here.',
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Find the nutrition and fitness support that fits your goals.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          if (records.isNotEmpty) ...[
            Text('Your membership', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final member in records)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _MembershipCard(member: member),
              ),
          ],
          if (memberships.isLoading) const LinearProgressIndicator(),
          if (memberships.hasError)
            _Failure(
              error: memberships.error!,
              onRetry: () => ref.invalidate(packageMembershipsProvider),
            ),
          const SizedBox(height: 16),
          Text('Available packages', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          if (_error != null)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ),
          catalog.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (error, stack) => _Failure(
              error: error,
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
                                  Text(
                                    item.name,
                                    style: theme.textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    _price(item.priceNpr),
                                    style: theme.textTheme.headlineMedium,
                                  ),
                                  Text(
                                    '${item.durationDays} days of support',
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
                                    onPressed:
                                        _busyId != null ||
                                            hasPending ||
                                            !memberships.hasValue ||
                                            memberships.hasError
                                        ? null
                                        : () => _select(item),
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

class _MembershipCard extends StatelessWidget {
  const _MembershipCard({required this.member});
  final PackageMembership member;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = member.status.name;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(member.package.name, style: theme.textTheme.titleLarge),
                Chip(
                  label: Text(
                    '${status[0].toUpperCase()}${status.substring(1)}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_price(member.package.priceNpr)),
            const SizedBox(height: 8),
            if (member.status == MembershipStatus.pending)
              const Text(
                'Your selection is saved. Your program starts after payment is verified.',
              )
            else ...[
              Text('Starts: ${_nepalDate(member.startAt!)}'),
              Text('Ends: ${_nepalDate(member.endAt!)}'),
              const SizedBox(height: 8),
              Text(
                member.status == MembershipStatus.active
                    ? '${member.daysRemaining} days remaining'
                    : member.status == MembershipStatus.scheduled
                    ? 'Your package starts on the date above.'
                    : 'This package has ended.',
                style: theme.textTheme.titleMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          error is PackageFailure
              ? (error as PackageFailure).message
              : 'We couldn’t load your packages. Please try again.',
        ),
        TextButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    ),
  );
}

String _price(int amount) => 'Rs. ${NumberFormat('#,##0').format(amount)}';
String _nepalDate(DateTime date) =>
    DateFormat('d MMM yyyy, HH:mm')
        .format(date.toUtc().add(const Duration(hours: 5, minutes: 45)));
