import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes/app_routes.dart';
import '../../../../app/theme/app_theme.dart';
import '../../domain/entities/package_entity.dart';
import '../controllers/package_management_controller.dart';
import '../widgets/empty_state_widget.dart';

class PackageManagementPage extends ConsumerWidget {
  const PackageManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(packageManagementControllerProvider);
    final controller = ref.read(packageManagementControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Package Management'),
        actions: [
          IconButton(
            tooltip: 'Package approvals',
            onPressed: () => context.push(AppRoutes.adminPackageApprovals),
            icon: const Icon(Icons.verified_outlined),
          ),
          IconButton(
            key: const Key('package_history_button'),
            tooltip: 'Package history',
            onPressed: () => context.push(AppRoutes.adminPackageHistory),
            icon: const Icon(Icons.history_rounded),
          ),
          IconButton(
            tooltip: 'Refresh packages',
            onPressed: state.isLoading ? null : controller.refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: state.isCreating
            ? null
            : () async {
                final packageName = await context.push<String>(
                  AppRoutes.adminCreatePackage,
                );
                if (packageName != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$packageName was created.')),
                  );
                }
              },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Create package'),
      ),
      body: _PackageListBody(state: state, onRefresh: controller.refresh),
    );
  }
}

class _PackageListBody extends StatelessWidget {
  final PackageManagementState state;
  final Future<void> Function() onRefresh;

  const _PackageListBody({required this.state, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (state.isLoading && state.packages.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Loading packages...',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }
    if (state.errorMessage != null && state.packages.isEmpty) {
      return EmptyStateWidget(
        icon: Icons.cloud_off_rounded,
        title: 'Failed to load packages',
        subtitle: state.errorMessage!,
        actionLabel: 'Retry',
        onAction: onRefresh,
      );
    }
    if (state.packages.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.inventory_2_outlined,
        title: 'No packages yet',
        subtitle: 'Create the first fitness package for FitNep customers.',
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          96 + MediaQuery.paddingOf(context).bottom,
        ),
        itemCount: state.packages.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) =>
            _PackageCard(package: state.packages[index]),
      ),
    );
  }
}

class _PackageCard extends ConsumerWidget {
  final PackageEntity package;

  const _PackageCard({required this.package});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(packageManagementControllerProvider.notifier);
    final isSaving = ref.watch(
      packageManagementControllerProvider.select((s) => s.isSaving),
    );

    final currency = NumberFormat.currency(
      locale: 'en_NP',
      symbol: 'NPR ',
      decimalDigits: package.price % 1 == 0 ? 0 : 2,
    );

    return Opacity(
      opacity: package.isActive ? 1.0 : 0.65,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: package.isActive
                          ? AppColors.primaryContainer
                          : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.fitness_center_rounded,
                      color: package.isActive
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                package.name,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            // Active / Inactive badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: package.isActive
                                    ? AppColors.statusActiveContainer
                                    : AppColors.statusInactiveContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                package.isActive ? 'Active' : 'Inactive',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: package.isActive
                                      ? AppColors.statusActive
                                      : AppColors.statusInactive,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${package.durationMonths} ${package.durationMonths == 1 ? 'month' : 'months'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    currency.format(package.price),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(),
              const SizedBox(height: 12),
              Text(
                package.featureDescription,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Edit button
                  OutlinedButton.icon(
                    onPressed: isSaving
                        ? null
                        : () async {
                            final updated = await context.push<PackageEntity>(
                              AppRoutes.adminEditPackage(package.id),
                              extra: package,
                            );
                            if (updated != null && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('${updated.name} was updated.'),
                                ),
                              );
                            }
                          },
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Deactivate / Activate button
                  TextButton.icon(
                    onPressed: isSaving
                        ? null
                        : () => _confirmToggleActive(
                            context,
                            controller,
                            package,
                          ),
                    icon: Icon(
                      package.isActive
                          ? Icons.block_rounded
                          : Icons.check_circle_outline_rounded,
                      size: 16,
                      color: package.isActive
                          ? AppColors.statusInactive
                          : AppColors.statusActive,
                    ),
                    label: Text(
                      package.isActive ? 'Deactivate' : 'Reactivate',
                      style: TextStyle(
                        color: package.isActive
                            ? AppColors.statusInactive
                            : AppColors.statusActive,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmToggleActive(
    BuildContext context,
    PackageManagementController controller,
    PackageEntity package,
  ) async {
    final willDeactivate = package.isActive;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          willDeactivate ? 'Deactivate Package?' : 'Reactivate Package?',
        ),
        content: Text(
          willDeactivate
              ? 'Customers will no longer see "${package.name}" in the package list. '
                    'Existing purchases will remain intact.'
              : 'Customers will be able to see and purchase "${package.name}" again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: willDeactivate
                  ? AppColors.statusInactive
                  : AppColors.statusActive,
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(willDeactivate ? 'Deactivate' : 'Reactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await controller.setPackageActiveStatus(
        id: package.id,
        isActive: !package.isActive,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              willDeactivate
                  ? '${package.name} was deactivated.'
                  : '${package.name} was reactivated.',
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString()),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}
