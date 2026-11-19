import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes/app_routes.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../admin/domain/entities/package_entity.dart';
import '../../../admin/domain/repositories/package_repository.dart';
import '../../../admin/presentation/controllers/package_management_controller.dart';
import '../../../admin/presentation/widgets/empty_state_widget.dart';
import '../../../purchases/presentation/controllers/membership_controller.dart';

// ── Customer-facing active-only packages provider ─────────────────────────────

class _ActivePackageState {
  final List<PackageEntity> packages;
  final bool isLoading;
  final String? errorMessage;

  const _ActivePackageState({
    this.packages = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  _ActivePackageState copyWith({
    List<PackageEntity>? packages,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return _ActivePackageState(
      packages: packages ?? this.packages,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class _ActivePackageController extends Notifier<_ActivePackageState> {
  late PackageRepository _repository;

  @override
  _ActivePackageState build() {
    _repository = ref.watch(packageRepositoryProvider);
    Future<void>.microtask(refresh);
    return const _ActivePackageState(isLoading: true);
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final packages = await _repository.getActivePackages();
      state = state.copyWith(packages: packages, isLoading: false);
    } catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: error.toString());
    }
  }
}

final _activePackageControllerProvider =
    NotifierProvider<_ActivePackageController, _ActivePackageState>(
      _ActivePackageController.new,
    );

// ── Page ──────────────────────────────────────────────────────────────────────

class PackageSelectionPage extends ConsumerWidget {
  const PackageSelectionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(_activePackageControllerProvider);
    final controller = ref.read(_activePackageControllerProvider.notifier);
    final membership = ref.watch(membershipControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Choose a Package'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: state.isLoading ? null : controller.refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _PackageSelectionBody(
        state: state,
        isPurchasing: membership.isPurchasing,
        onRefresh: controller.refresh,
        onPurchase: (package) => _purchasePackage(context, ref, package),
      ),
    );
  }
}

class _PackageSelectionBody extends StatelessWidget {
  final _ActivePackageState state;
  final bool isPurchasing;
  final Future<void> Function() onRefresh;
  final Future<void> Function(PackageEntity package) onPurchase;

  const _PackageSelectionBody({
    required this.state,
    required this.isPurchasing,
    required this.onRefresh,
    required this.onPurchase,
  });

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
        title: 'No packages available',
        subtitle:
            'No fitness packages are currently available. Check back later.',
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        itemCount: state.packages.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _CustomerPackageCard(
          package: state.packages[index],
          isPurchasing: isPurchasing,
          onPurchase: onPurchase,
        ),
      ),
    );
  }
}

class _CustomerPackageCard extends StatelessWidget {
  final PackageEntity package;
  final bool isPurchasing;
  final Future<void> Function(PackageEntity package) onPurchase;

  const _CustomerPackageCard({
    required this.package,
    required this.isPurchasing,
    required this.onPurchase,
  });

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(
      locale: 'en_NP',
      symbol: 'NPR ',
      decimalDigits: package.price % 1 == 0 ? 0 : 2,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.fitness_center_rounded,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        package.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${package.durationMonths} '
                        '${package.durationMonths == 1 ? 'month' : 'months'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      currency.format(package.price),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(),
            const SizedBox(height: 12),
            Text(
              package.featureDescription,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                key: Key('select_package_${package.id}'),
                onPressed: isPurchasing ? null : () => onPurchase(package),
                child: isPurchasing
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('Purchase ${package.name}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _purchasePackage(
  BuildContext context,
  WidgetRef ref,
  PackageEntity package,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Purchase ${package.name}?'),
      content: Text(
        'Your price, duration, and included features will be saved as your purchased membership terms.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Confirm Purchase'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  try {
    await ref
        .read(membershipControllerProvider.notifier)
        .purchasePackage(package.id);
    if (context.mounted) context.go(AppRoutes.clientMembership);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(error.toString())));
  }
}
